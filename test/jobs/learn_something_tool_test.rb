require "test_helper"

# The plan half of the D19 contract: a plan tool is goal capture with
# framing, riding the same Goals::BreakDown pipeline as every goal.
class LearnSomethingToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "learn_something",
      inputs: { "topic" => "Spanish", "angle" => "conversational by June" }
    )
  end

  test "creates a planned goal through the shared breakdown pipeline" do
    stub_llm(
      sections: [ "education" ],
      target_on: "2027-06-01",
      steps: [
        { title: "Set up a flashcard deck with the 100 most common words", due_on: Date.current.iso8601, sections: [ "education" ] },
        { title: "Hold a 5-minute self-introduction out loud", due_on: Date.tomorrow.iso8601, sections: [] }
      ]
    )

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?

    goal = @run.items.grep(Goal).sole
    assert_equal "Learn Spanish", goal.title
    assert_equal "conversational by June", goal.description
    assert_equal Date.new(2027, 6, 1), goal.target_on
    assert_not_nil goal.broken_down_at, "the goal card must not be left spinning"
    assert_includes goal.sections, sections(:education)

    steps = @run.items.grep(Task).sort_by(&:id)
    assert_equal 2, steps.count
    assert_equal [ goal, goal ], steps.map(&:goal), "steps belong to the goal like any breakdown"
    assert steps.first.today?
    assert steps.second.later?
  end

  test "the model call carries the tool's framing brief" do
    stub_llm(sections: [], target_on: nil, steps: [])

    ToolRunJob.perform_now(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("personal study plan") && request.body.include?("conversational by June")
    end
  end

  test "the plan is filed under the tool's section even if the model files it elsewhere" do
    stub_llm(sections: [ "hobbies" ], target_on: nil, steps: [ { title: "Watch a lecture" } ])

    ToolRunJob.perform_now(@run)

    goal = @run.reload.items.grep(Goal).sole
    assert_includes goal.sections, sections(:education), "always findable where the tool lives"
    assert_includes goal.sections, sections(:hobbies), "the model's filing is kept too"
  end

  test "a provider error fails the run but leaves an ordinary retryable goal" do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "Incorrect API key" } }.to_json)

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.failed?

    goal = @run.items.grep(Goal).sole
    assert_empty goal.tasks
    assert_not_nil goal.broken_down_at, "a failed run must not leave the goal spinning"
    assert_not goal.breaking_down?
  end

  private
    def stub_llm(sections:, target_on:, steps:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          sections: sections, target_on: target_on, steps: steps
        }.to_json } } ] }.to_json
      )
    end
end
