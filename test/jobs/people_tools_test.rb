require "test_helper"

# The People tool wave (docs/PEOPLE.md §4): gift ideas on the shared draft
# contract and person_context, plan-a-get-together landing its Event by
# code before the plan pipeline runs.
class PeopleToolsTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "gift ideas draft from the person's record and file under People plus theirs" do
    person = users(:one).people.create!(
      name: "Sam", relationship: "college friend", notes: "Deep into sourdough lately"
    )
    person.sections << sections(:hobbies)

    stub_draft(body: "1. A banneton basket — because of the sourdough thing.")
    run = users(:one).tool_runs.create!(
      tool_slug: "gift_ideas",
      inputs: { "person_id" => person.id.to_s, "occasion" => "birthday", "budget" => "under $30" }
    )
    run_and_add_all(run)

    assert run.reload.done?
    note = run.items.grep(Note).sole
    assert_equal "Gift ideas for Sam", note.title
    assert_equal [ sections(:people), sections(:hobbies) ].sort_by(&:id), note.sections.sort_by(&:id)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Deep into sourdough") &&
        request.body.include?("college friend") &&
        request.body.include?("under $30")
    end
  end

  test "a vanished person fails the gift run gracefully" do
    run = users(:one).tool_runs.create!(tool_slug: "gift_ideas", inputs: { "person_id" => "999999" })
    run_and_add_all(run)

    assert run.reload.failed?
    assert_match(/gone or no longer shared/, run.error)
  end

  test "get-together with a date lands the event by code and plans backwards" do
    date = 3.weeks.from_now.to_date
    stub_plan(steps: [
      { title: "Text the Nguyens the date", due_on: Date.current.iso8601, sections: [ "people" ] },
      { title: "Shop for taco fixings", due_on: (date - 1).iso8601, sections: [ "money" ] }
    ])

    run = users(:one).tool_runs.create!(
      tool_slug: "get_together",
      inputs: { "occasion" => "Taco night with the Nguyens", "who" => "the Nguyens", "on" => date.iso8601 }
    )
    run_and_add_all(run)

    assert run.reload.done?

    event = run.items.grep(Event).sole
    assert_equal "Taco night with the Nguyens", event.title
    assert event.all_day?
    assert_equal date, event.starts_at.to_date
    assert_equal [ sections(:people) ], event.sections.to_a

    goal = run.items.grep(Goal).sole
    assert_equal "Taco night with the Nguyens", goal.title
    assert_match(/the Nguyens/, goal.description)
    assert_equal 2, run.items.grep(Task).size

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("small social gathering") && request.body.include?(date.iso8601)
    end
  end

  test "get-together without a date makes picking one the plan's problem, not an event" do
    stub_plan(steps: [ { title: "Propose two dates to the book club" } ])

    run = users(:one).tool_runs.create!(tool_slug: "get_together", inputs: { "occasion" => "Book club" })
    run_and_add_all(run)

    assert run.reload.done?
    assert_empty run.items.grep(Event), "no date, no event — the plan proposes dates instead"
    assert_requested(:post, ENDPOINT) { |request| request.body.include?("proposing 2") }
  end

  test "a model failure still leaves the get-together's date on the calendar" do
    date = 2.weeks.from_now.to_date
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "bad key" } }.to_json)

    run = users(:one).tool_runs.create!(
      tool_slug: "get_together",
      inputs: { "occasion" => "Game night", "on" => date.iso8601 }
    )
    run_and_add_all(run)

    assert run.reload.failed?
    assert_equal date, run.items.grep(Event).sole.starts_at.to_date,
      "the deterministic part lands first and survives"
  end

  test "make-new-friends plans around recurring venues and the user's hobby lenses" do
    Hobbies::Lens.find_or_create!("Climbing")
    stub_plan(steps: [ { title: "Find two recurring groups to try", sections: [ "people" ] } ])

    run = users(:one).tool_runs.create!(
      tool_slug: "make_new_friends",
      inputs: { "interests" => "board games", "constraints" => "evenings only" }
    )
    run_and_add_all(run)

    assert run.reload.done?
    goal = run.items.grep(Goal).sole
    assert_equal "Make new friends", goal.title
    assert_match(/board games/, goal.description)
    assert_includes goal.sections, sections(:people)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("recurring") &&
        request.body.include?("Climbing") &&
        request.body.include?("evenings only")
    end
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

    def stub_plan(steps:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          sections: [ "people" ], target_on: nil, steps: steps
        }.to_json } } ] }.to_json
      )
    end
end
