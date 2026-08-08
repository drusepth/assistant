require "test_helper"

# The caregiving and bereavement Situations (docs/PEOPLE.md §4): each is one
# plan-tool class with a rich cross-section brief on the shared plan_goal!
# contract — the D7 pattern Moving proved.
class SituationsToolsTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "caregiver plans a cross-section goal carrying the marathon framing" do
    stub_plan(steps: [
      { title: "Write down Mom's doctors and medications as known", sections: [ "health" ] },
      { title: "Talk with Dan about splitting the driving", sections: [ "people" ] }
    ])

    run = users(:one).tool_runs.create!(
      tool_slug: "caregiver",
      inputs: { "who" => "my mom", "situation" => "memory slipping", "details" => "brother Dan lives nearby" }
    )
    ToolRunJob.perform_now(run)

    assert run.reload.done?
    goal = run.items.grep(Goal).sole
    assert_equal "Care for my mom", goal.title
    assert_match(/memory slipping/, goal.description)
    assert_includes goal.sections, sections(:people)
    assert_equal 2, run.items.grep(Task).size

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("caregiver") &&
        request.body.include?("marathon") &&
        request.body.include?("brother Dan lives nearby")
    end
  end

  test "bereavement plans gently and carries the user's role" do
    stub_plan(steps: [ { title: "Request certified copies of the death certificate", sections: [ "rights" ] } ])

    run = users(:one).tool_runs.create!(
      tool_slug: "bereavement",
      inputs: { "who" => "my dad", "details" => "I'm the executor" }
    )
    ToolRunJob.perform_now(run)

    assert run.reload.done?
    goal = run.items.grep(Goal).sole
    assert_equal "After losing my dad", goal.title
    assert_equal "I'm the executor", goal.description
    assert_includes goal.sections, sections(:people)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("grieving") &&
        request.body.include?("No productivity cheer") &&
        request.body.include?("I'm the executor")
    end
  end

  test "both register on the People section" do
    tools = Tool.for_section(sections(:people)).map(&:slug)
    assert_includes tools, "caregiver"
    assert_includes tools, "bereavement"
  end

  private
    def stub_plan(steps:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          sections: [ "people" ], target_on: nil, steps: steps
        }.to_json } } ] }.to_json
      )
    end
end
