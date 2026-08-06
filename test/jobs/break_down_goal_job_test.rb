require "test_helper"

class BreakDownGoalJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @goal = users(:one).goals.create!(title: "Find a new job")
  end

  test "breaks the goal into scheduled, filed tasks and stamps broken_down_at" do
    stub_llm(
      sections: [ "career", "not-a-real-slug" ],
      target_on: "2026-10-01",
      steps: [
        { title: "Update resume", notes: "Focus on recent projects", due_on: Date.current.iso8601, sections: [ "career" ] },
        { title: "List 10 companies to apply to", due_on: Date.tomorrow.iso8601, sections: [] }
      ]
    )

    BreakDownGoalJob.perform_now(@goal)

    @goal.reload
    assert_equal [ sections(:career) ], @goal.sections.to_a
    assert_equal Date.new(2026, 10, 1), @goal.target_on
    assert_not_nil @goal.broken_down_at

    first, second = @goal.tasks.order(:id).to_a
    assert_equal "Update resume", first.title
    assert_equal "Focus on recent projects", first.notes
    assert_equal Date.current, first.due_on
    assert first.today?, "a step due today lands in the Today column"
    assert_equal [ sections(:career) ], first.sections.to_a
    assert_equal "List 10 companies to apply to", second.title
    assert second.later?, "a step due later stays in the backlog"
  end

  test "does not re-break a goal that already has steps" do
    @goal.tasks.create!(user: users(:one), title: "Existing step")

    BreakDownGoalJob.perform_now(@goal)

    assert_not_requested :post, ENDPOINT
    assert_equal 1, @goal.tasks.count
  end

  test "append mode adds steps to an already-planned goal" do
    @goal.tasks.create!(user: users(:one), title: "Existing step")
    stub_llm(sections: [], target_on: nil, steps: [ { title: "A missing step" } ])

    BreakDownGoalJob.perform_now(@goal, append: true)

    assert_equal [ "Existing step", "A missing step" ], @goal.tasks.order(:id).pluck(:title)
  end

  test "never overwrites hand-set sections or target date" do
    @goal.update!(target_on: Date.new(2026, 9, 1))
    @goal.sections << sections(:money)
    stub_llm(sections: [ "career" ], target_on: "2026-12-01", steps: [ { title: "Update resume" } ])

    BreakDownGoalJob.perform_now(@goal)

    @goal.reload
    assert_equal [ sections(:money) ], @goal.sections.to_a
    assert_equal Date.new(2026, 9, 1), @goal.target_on
    assert_equal 1, @goal.tasks.count
  end

  test "permanent provider errors leave the goal unplanned but still stamp broken_down_at" do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "Incorrect API key" } }.to_json)

    BreakDownGoalJob.perform_now(@goal)

    @goal.reload
    assert_empty @goal.tasks
    assert_not_nil @goal.broken_down_at, "a failed attempt must not leave the goal spinning"
    assert_not @goal.breaking_down?
  end

  test "a transient error leaves the goal breaking down while a retry is pending" do
    stub_request(:post, ENDPOINT).to_return(status: 429, body: "slow down")

    BreakDownGoalJob.perform_now(@goal)

    @goal.reload
    assert_nil @goal.broken_down_at, "a pending retry must not drop the goal out of breaking-down and back"
    assert @goal.breaking_down?
    assert_enqueued_jobs 1, only: BreakDownGoalJob
  end

  test "a transient error that never clears stamps broken_down_at once out of chances" do
    stub_request(:post, ENDPOINT).to_return(status: 429, body: "slow down")

    perform_enqueued_jobs { BreakDownGoalJob.perform_later(@goal) }

    @goal.reload
    assert_empty @goal.tasks
    assert_not_nil @goal.broken_down_at
    assert_not @goal.breaking_down?
    assert_requested :post, ENDPOINT, times: RetriesModelCalls::ATTEMPTS
  end

  test "skips users without a configured model profile" do
    goal = users(:outsider).goals.create!(title: "Get fit")

    BreakDownGoalJob.perform_now(goal)

    assert_not_requested :post, ENDPOINT
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
