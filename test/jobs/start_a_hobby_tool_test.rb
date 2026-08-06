require "test_helper"

# The Hobbies plan tool: curiosity in, lens + cheap-first-taste plan out,
# through the same shared breakdown pipeline as every goal.
class StartAHobbyToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "start_a_hobby",
      inputs: { "hobby" => "pottery", "about" => "small apartment, tiny budget" }
    )
  end

  test "creates the hobby lens and a planned goal filed under it" do
    stub_llm(
      sections: [ "hobbies" ],
      steps: [
        { title: "Pinch a bowl from air-dry clay tonight", due_on: Date.current.iso8601, sections: [ "pottery" ] },
        { title: "Look up the community studio's open hours", due_on: Date.tomorrow.iso8601, sections: [] }
      ]
    )

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?

    lens = Section.find_by(slug: "pottery")
    assert lens.custom?, "the hobby gets its own lens"
    assert_equal sections(:hobbies), lens.parent

    goal = @run.items.grep(Goal).sole
    assert_equal "Get into Pottery", goal.title
    assert_equal "small apartment, tiny budget", goal.description
    assert_includes goal.sections, sections(:hobbies)
    assert_includes goal.sections, lens, "filed under its own lens too"
    assert_not_nil goal.broken_down_at

    steps = @run.items.grep(Task).sort_by(&:id)
    assert_equal 2, steps.count
    assert_includes steps.first.sections, lens, "the lens exists before the model call, so steps can be filed under it"
  end

  test "the model call carries the cheap-first-taste brief and the user's constraints" do
    stub_llm(sections: [], steps: [])

    ToolRunJob.perform_now(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("cheapest") && request.body.include?("small apartment, tiny budget")
    end
  end

  test "reuses an existing lens instead of duplicating it" do
    existing = Hobbies::Lens.find_or_create!("Pottery")
    stub_llm(sections: [], steps: [])

    assert_no_difference "Section.count" do
      ToolRunJob.perform_now(@run)
    end

    assert_includes @run.reload.items.grep(Goal).sole.sections, existing
  end

  test "a provider error fails the run but leaves an ordinary retryable goal" do
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.failed?

    goal = @run.items.grep(Goal).sole
    assert_empty goal.tasks
    assert_not_nil goal.broken_down_at, "a failed run must not leave the goal spinning"
  end

  private
    def stub_llm(sections:, steps:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          sections: sections, target_on: nil, steps: steps
        }.to_json } } ] }.to_json
      )
    end
end
