require "test_helper"

# The Health insurance-and-access slate (docs/HEALTH.md): find-care,
# insurance-explainer, compare-plans — each exercising the shared Base
# contracts rather than re-proving the whole pipeline.
class HealthToolsTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "find-care drafts a search plan with the verify-in-network footer appended by code" do
    users(:one).documents.create!(title: "Acme PPO Summary of Benefits", summary: "Acme Health PPO, $30 copay")

    stub_draft(body: "Start with the Acme member portal...")
    run = users(:one).tool_runs.create!(tool_slug: "find_care", inputs: { "specialty" => "dentist" })
    ToolRunJob.perform_now(run)

    assert run.reload.done?
    note = run.items.grep(Note).sole
    assert_equal "Finding care — dentist", note.title
    assert_match(/not the same as in-network/, note.body)
    assert_includes note.sections, sections(:health)

    assert_requested(:post, ENDPOINT) { |request| request.body.include?("Acme Health PPO") }
  end

  test "find-care never sees another user's unshared insurance documents" do
    users(:two).documents.create!(title: "Bob's health insurance card", summary: "MegaCorp HMO")

    stub_draft(body: "Your plan...")
    run = users(:one).tool_runs.create!(tool_slug: "find_care", inputs: { "specialty" => "eye doctor" })
    ToolRunJob.perform_now(run)

    assert run.reload.done?
    assert_requested(:post, ENDPOINT) { |request| !request.body.include?("MegaCorp") }
  end

  test "insurance-explainer explains the chosen document, appends the disclaimer, and routes onward" do
    document = users(:one).documents.create!(
      title: "Acme SBC", extracted_text: "Deductible: $1,500. ER: $250 copay after deductible."
    )
    document.sections << sections(:health)

    stub_request(:post, ENDPOINT).to_return(status: 200, body: { choices: [ { message: { content: {
      draft: { title: "Your Acme plan, explained", body: "You pay the first $1,500 each year..." },
      follow_ups: [ { title: "Find the member portal login" } ],
      next_tools: [
        { slug: "insurance_appeal", reason: "This mentions a denial", inputs: { "document_id" => "999" } },
        { slug: "tutor", reason: "not allowed" }
      ]
    }.to_json } } ] }.to_json)

    run = users(:one).tool_runs.create!(tool_slug: "insurance_explainer", inputs: { "document_id" => document.id.to_s })
    ToolRunJob.perform_now(run)

    assert run.reload.done?
    note = run.items.grep(Note).sole
    assert_equal "Your Acme plan, explained", note.title
    assert_match(/not coverage advice/, note.body)
    assert_equal [ sections(:health) ], note.sections.to_a

    steps = run.next_steps
    assert_equal [ "insurance_appeal" ], steps.map { |step| step.tool.slug }, "unallowed slugs are dropped"
    assert_equal document.id.to_s, steps.sole.inputs["document_id"],
      "code attaches the real document — the model's id never survives"
  end

  test "compare-plans reads both documents and refuses to compare a document with itself" do
    plan_a = users(:one).documents.create!(title: "Acme PPO", extracted_text: "Deductible $1,500")
    plan_b = users(:one).documents.create!(title: "Zenith HMO", extracted_text: "Deductible $500")

    stub_draft(body: "Plan A costs more up front...")
    run = users(:one).tool_runs.create!(
      tool_slug: "compare_plans",
      inputs: { "plan_a_id" => plan_a.id.to_s, "plan_b_id" => plan_b.id.to_s, "household" => "family of four" }
    )
    ToolRunJob.perform_now(run)

    assert run.reload.done?
    note = run.items.grep(Note).sole
    assert_equal "Compared — Acme PPO vs. Zenith HMO", note.title
    assert_match(/plan documents control/, note.body)
    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("family of four") &&
        request.body.include?("Deductible $1,500") && request.body.include?("Deductible $500")
    end

    same = users(:one).tool_runs.create!(
      tool_slug: "compare_plans",
      inputs: { "plan_a_id" => plan_a.id.to_s, "plan_b_id" => plan_a.id.to_s }
    )
    ToolRunJob.perform_now(same)
    assert same.reload.failed?
    assert_match(/same document/, same.error)
  end

  test "start-a-practice plans a gentle goal through the shared pipeline" do
    stub_request(:post, ENDPOINT).to_return(status: 200, body: { choices: [ { message: { content: {
      sections: [ "health" ], target_on: nil,
      steps: [
        { title: "Sit for five minutes after breakfast", due_on: Date.tomorrow.iso8601, sections: [ "health" ] },
        { title: "Try a free guided session from the library", sections: [ "health" ] }
      ]
    }.to_json } } ] }.to_json)

    run = users(:one).tool_runs.create!(
      tool_slug: "start_a_practice",
      inputs: { "practice" => "meditation", "shape" => "10 minutes before work" }
    )
    ToolRunJob.perform_now(run)

    assert run.reload.done?
    goal = run.items.grep(Goal).sole
    assert_equal "Build a meditation practice", goal.title
    assert_equal "10 minutes before work", goal.description
    assert_not_nil goal.broken_down_at
    assert_includes goal.sections, sections(:health)
    assert_equal 2, run.items.grep(Task).size

    assert_requested(:post, ENDPOINT) { |request| request.body.include?("calming mind-body practice") }
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
