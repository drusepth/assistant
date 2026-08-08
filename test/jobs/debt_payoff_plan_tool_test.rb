require "test_helper"

# The debt payoff planner (docs/MONEY.md §5.3): a plan tool on the shared
# breakdown pipeline, whose brief carries the honesty boundary.
class DebtPayoffPlanToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup { @user = users(:one) }

  test "plans the payoff as a goal with filed steps, carrying the chosen method" do
    stub_plan(steps: [
      { title: "List every debt on one page", due_on: Date.current.iso8601, sections: [ "debt" ] },
      { title: "Put every minimum on autopay", due_on: (Date.current + 3).iso8601, sections: [ "debt", "money" ] }
    ])

    run = perform(debts: "Visa 4,200 at 24%, min 95\nCar loan about 8k",
      method: Tool::DebtPayoffPlan::METHODS.first, monthly_extra: "200")

    assert run.done?, run.error
    goal = run.items.grep(Goal).sole
    assert_equal "Pay off my debt", goal.title
    assert_match(/Visa 4,200/, goal.description)
    assert_match(/200/, goal.description)
    assert_includes goal.sections.map(&:slug), "debt"
    assert_equal 2, run.items.grep(Task).size

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Avalanche") &&
        request.body.include?("don't relitigate the choice") &&
        request.body.include?("Never recommend a specific financial product")
    end
  end

  test "with no method chosen the brief asks the model to pick and say why" do
    stub_plan(steps: [ { title: "List every debt", due_on: nil, sections: [ "debt" ] } ])

    perform(debts: "Two cards, roughly equal")

    assert_requested(:post, ENDPOINT) { |request| request.body.include?("asked you to choose the method") }
  end

  test "an existing savings-and-debt envelope anchors the extra payment" do
    @user.budget_categories.create!(name: "Debt payoff", group: "savings_debt", monthly_target_cents: 30_000)
    stub_plan(steps: [ { title: "List every debt", due_on: nil, sections: [ "debt" ] } ])

    perform(debts: "Visa 4,200")

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("300 USD a month") && request.body.include?("rather than inventing one")
    end
  end

  test "a failed plan leaves an ordinary retryable goal" do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "Incorrect API key" } }.to_json)

    run = perform(debts: "Visa 4,200")

    assert run.failed?
    goal = @user.goals.find_by!(title: "Pay off my debt")
    assert_not_nil goal.broken_down_at, "the goal card can't spin forever"
  end

  private
    def perform(debts:, method: nil, monthly_extra: nil)
      run = @user.tool_runs.create!(tool_slug: "debt_payoff_plan",
        inputs: { "debts" => debts, "method" => method, "monthly_extra" => monthly_extra }.compact)
      ToolRunJob.perform_now(run)
      run.reload
    end

    def stub_plan(steps:)
      stub_request(:post, ENDPOINT).to_return(status: 200, body: {
        choices: [ { message: { content: { steps: steps, sections: [ "debt", "money" ] }.to_json } } ]
      }.to_json)
    end
end
