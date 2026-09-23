require "test_helper"

# The M2.3 coverage slate + the M2.4 "moving" Situation, each exercising
# the shared Base contracts (DRAFT_FORMAT handling, plan_goal!) rather than
# re-proving the whole pipeline.
class CoverageToolsTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "doctor-visit prep drafts from the user's own health items" do
    event = users(:one).events.create!(title: "Physical with Dr. Reyes", starts_at: 3.months.ago, all_day: true)
    event.sections << sections(:health)
    users(:two).events.create!(title: "Bob's cardiology consult", starts_at: 2.months.ago, all_day: true)
      .sections << sections(:health)

    stub_draft(body: "Questions to ask...")
    run = users(:one).tool_runs.create!(tool_slug: "doctor_visit_prep", inputs: { "reason" => "annual physical" })
    run_and_add_all(run)

    assert run.reload.done?
    note = run.items.grep(Note).sole
    assert_equal "Doctor-visit prep sheet", note.title
    assert_equal [ sections(:health) ], note.sections.to_a

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Physical with Dr. Reyes") && !request.body.include?("cardiology consult")
    end
  end

  test "cancel-subscription drafts with the service in the title fallback" do
    stub_draft(body: "Dear Streamly, I am cancelling...")
    run = users(:one).tool_runs.create!(tool_slug: "cancel_subscription", inputs: { "service" => "Streamly" })
    run_and_add_all(run)

    note = run.reload.items.grep(Note).sole
    assert_equal "Cancel Streamly", note.title
    assert_equal [ sections(:subscriptions) ], note.sections.to_a
  end

  test "reconnect drafts from the person's record and files under People plus theirs" do
    person = users(:one).people.create!(name: "Mom", relationship: "mother", notes: "Loves her garden")
    person.sections << sections(:health)

    stub_draft(body: "Hi Mom — been thinking about you...")
    run = users(:one).tool_runs.create!(tool_slug: "reconnect", inputs: { "person_id" => person.id.to_s })
    run_and_add_all(run)

    note = run.reload.items.grep(Note).sole
    assert_equal "Message to Mom", note.title
    assert_equal [ sections(:people), sections(:health) ].sort_by(&:id), note.sections.sort_by(&:id)

    assert_requested(:post, ENDPOINT) { |request| request.body.include?("Loves her garden") }
  end

  test "a vanished person fails the reconnect run gracefully" do
    run = users(:one).tool_runs.create!(tool_slug: "reconnect", inputs: { "person_id" => "999999" })
    run_and_add_all(run)

    assert run.reload.failed?
    assert_match(/gone or no longer shared/, run.error)
  end

  test "moving plans a cross-section goal through the shared pipeline" do
    stub_request(:post, ENDPOINT).to_return(status: 200, body: { choices: [ { message: { content: {
      sections: [ "money" ], target_on: nil,
      steps: [
        { title: "Give written notice to the landlord", due_on: Date.current.iso8601, sections: [ "renting" ] },
        { title: "Get moving quotes", sections: [ "money" ] }
      ]
    }.to_json } } ] }.to_json)

    run = users(:one).tool_runs.create!(
      tool_slug: "moving",
      inputs: { "destination" => "Austin", "timing" => "lease is up June 30" }
    )
    run_and_add_all(run)

    assert run.reload.done?
    goal = run.items.grep(Goal).sole
    assert_equal "Move to Austin", goal.title
    assert_match(/June 30/, goal.description)
    assert_not_nil goal.broken_down_at

    steps = run.items.grep(Task)
    assert_equal 2, steps.size
    assert_equal [ sections(:renting) ], steps.first.sections.to_a, "steps carry their own cross-section tags"

    assert_requested(:post, ENDPOINT) { |request| request.body.include?("household move") }
  end

  private
    def stub_draft(body:, title: nil, follow_ups: [])
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          draft: { title: title, body: body }, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
