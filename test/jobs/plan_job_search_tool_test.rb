require "test_helper"

class PlanJobSearchToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "creates the paced search plan with the cadence brief" do
    run = users(:one).tool_runs.create!(
      tool_slug: "plan_job_search",
      inputs: { "target" => "first dev job", "constraints" => "can't take a pay cut" }
    )
    stub_llm(
      sections: [ "career" ],
      target_on: nil,
      steps: [
        { title: "Update the work-history note and log recent wins", due_on: Date.current.iso8601, sections: [ "career" ] },
        { title: "Apply: Initech junior role", due_on: Date.tomorrow.iso8601, sections: [ "career" ] }
      ]
    )

    ToolRunJob.perform_now(run)

    run.reload
    assert run.done?

    goal = run.items.grep(Goal).sole
    assert_equal "Job search: first dev job", goal.title
    assert_equal "can't take a pay cut", goal.description
    assert_includes goal.sections, sections(:career)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("pace beats panic") && request.body.include?("can't take a pay cut")
    end
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
