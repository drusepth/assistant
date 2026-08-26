require "test_helper"

# The enrollment door (docs/EDUCATION_PLAN.md §6): one run lands the whole
# spine — a Subject with its tree (commons or generated) plus the same paced
# Goal→Tasks plan as before, aimed at the first topic.
class LearnSomethingToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "learn_something",
      inputs: { "topic" => "Spanish", "angle" => "conversational by June" }
    )
  end

  test "creates the subject with a generated tree and a planned goal aimed at its first topic" do
    stub_tree_then_plan

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?

    subject = @run.items.grep(Subject).sole
    assert_equal "Spanish", subject.title
    assert_equal "conversational by June", subject.interest_frame
    assert_equal [ "Sounds and greetings" ], subject.strands.map(&:title)
    assert_equal 2, subject.leaf_count
    assert subject.tree_built_at.present?
    assert_includes subject.sections, sections(:education)

    goal = @run.items.grep(Goal).sole
    assert_equal "Learn Spanish", goal.title
    assert_equal Date.new(2027, 6, 1), goal.target_on
    assert_not_nil goal.broken_down_at, "the goal card must not be left spinning"
    assert_includes goal.sections, sections(:education)

    assert_equal goal, subject.current_topic.goal, "the plan is aimed at the first topic"

    steps = @run.items.grep(Task).sort_by(&:id)
    assert_equal 2, steps.count
    assert_equal [ goal, goal ], steps.map(&:goal), "steps belong to the goal like any breakdown"
  end

  test "a topic that names a commons course enrolls instead of generating" do
    run = users(:one).tool_runs.create!(
      tool_slug: "learn_something",
      inputs: { "topic" => "Civics & how power works" }
    )
    stub_llm(sections: [ "education" ], target_on: nil, steps: [ { title: "Read the foundations strand" } ])

    ToolRunJob.perform_now(run)

    subject = run.reload.items.grep(Subject).sole
    assert_equal "civics", subject.commons_key
    assert_operator subject.leaf_count, :>, 10
    assert_requested(:post, ENDPOINT, times: 1)  # no tree generation call for a shelf course
  end

  test "running it again for an enrolled course reuses the subject" do
    run = users(:one).tool_runs.create!(
      tool_slug: "learn_something",
      inputs: { "topic" => "Everyday math" }
    )
    stub_llm(sections: [], target_on: nil, steps: [])

    assert_no_difference "Subject.count" do
      ToolRunJob.perform_now(run)
    end
    assert_equal subjects(:algebra), run.reload.items.grep(Subject).sole
  end

  test "the plan call carries the tool's framing brief" do
    stub_tree_then_plan

    ToolRunJob.perform_now(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("personal study plan") && request.body.include?("conversational by June")
    end
  end

  test "a provider error fails the run but leaves the subject, retryable from its page" do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "Incorrect API key" } }.to_json)

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.failed?

    subject = users(:one).subjects.find_by(title: "Spanish")
    assert_empty subject.topics
    assert_not_nil subject.tree_built_at, "a failed run must not leave the syllabus spinning"
    assert_not subject.building_tree?
  end

  private
    TREE = {
      strands: [
        { title: "Sounds and greetings", topics: [
          { title: "The Spanish alphabet and its sounds", summary: "Pronounce any written word." },
          { title: "Greetings and introductions", summary: "Hold a first exchange out loud." }
        ] }
      ]
    }.freeze

    def stub_tree_then_plan
      stub_request(:post, ENDPOINT).to_return(
        { status: 200, body: { choices: [ { message: { content: TREE.to_json } } ] }.to_json },
        { status: 200, body: { choices: [ { message: { content: {
          sections: [ "education" ], target_on: "2027-06-01",
          steps: [
            { title: "Set up a flashcard deck with the 100 most common words", due_on: Date.current.iso8601, sections: [ "education" ] },
            { title: "Hold a 5-minute self-introduction out loud", due_on: Date.tomorrow.iso8601, sections: [] }
          ]
        }.to_json } } ] }.to_json }
      )
    end

    def stub_llm(sections:, target_on:, steps:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          sections: sections, target_on: target_on, steps: steps
        }.to_json } } ] }.to_json
      )
    end
end
