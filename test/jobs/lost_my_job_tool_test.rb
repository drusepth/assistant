require "test_helper"

# The second Situation (docs/CAREER.md §3.7): one plan spanning Career,
# Money, Benefits, and Health — the cross-section brief doing the work.
class LostMyJobToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "creates a cross-section recovery plan through the shared breakdown" do
    run = users(:one).tool_runs.create!(
      tool_slug: "lost_my_job",
      inputs: { "last_day" => "last Friday", "details" => "two weeks severance offered, family on my insurance" }
    )
    stub_llm(
      sections: [ "career", "money" ],
      target_on: nil,
      steps: [
        { title: "File for unemployment online", due_on: Date.current.iso8601, sections: [ "benefits" ] },
        { title: "Compare COBRA against a marketplace plan", due_on: Date.tomorrow.iso8601, sections: [ "health", "money" ] },
        { title: "List which bills can flex this month", due_on: Date.tomorrow.iso8601, sections: [ "money" ] }
      ]
    )

    ToolRunJob.perform_now(run)

    run.reload
    assert run.done?

    goal = run.items.grep(Goal).sole
    assert_equal "Get steady after the job loss", goal.title
    assert_includes goal.description, "Last day: last Friday"
    assert_includes goal.description, "severance"
    # The plan is findable everywhere the Situation lives.
    %i[ career money benefits health ].each do |slug|
      assert_includes goal.sections, sections(slug)
    end

    steps = run.items.grep(Task)
    assert_equal 3, steps.count
    assert_includes steps.flat_map(&:sections), sections(:benefits)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("file for unemployment THIS WEEK") &&
        request.body.include?("two weeks severance")
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
