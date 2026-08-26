require "test_helper"

# The homework-tonight door (docs/EDUCATION_PLAN.md §6): guided, never
# done, no syllabus required.
class ExplainThisToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "the session opens from the pasted thing with the Socratic rules in force" do
    run = users(:one).tool_runs.create!(
      tool_slug: "explain_this",
      inputs: { "puzzle" => "Solve for x: 3x + 7 = 22", "learner" => "my 9-year-old" }
    )
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: "This is a balance puzzle — what could we take off both sides first?" } } ] }.to_json
    )

    ToolRunJob.perform_now(run)

    assert run.reload.done?
    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("3x + 7 = 22") &&
        request.body.include?("guided, never answered outright") &&
        request.body.include?("my 9-year-old")
    end
  end
end
