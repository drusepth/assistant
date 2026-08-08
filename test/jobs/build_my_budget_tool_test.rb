require "test_helper"

# The budget-drafting tool (docs/MONEY.md §3.2, D-budget-envelopes):
# code aggregates, the model proposes, suggest-and-apply lands it — and a
# hand-set target is never overwritten.
class BuildMyBudgetToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @account = @user.spending_accounts.create!(name: "Checking", kind: "checking")
  end

  test "drafts envelopes from imported spending and explains where they came from" do
    3.times { |i| spend("SAFEWAY", 48_000, on: Date.current - (i * 30)) }
    2.times { |i| spend("NETFLIX.COM", 1_599, on: Date.current - (i * 30)) }

    stub_budget(categories: [
      { name: "Groceries", group: "needs", monthly_target: 520, why: "your 3-month average is 480" },
      { name: "Streaming & subscriptions", group: "wants", monthly_target: 20, why: "Netflix at 15.99/mo" }
    ], summary: { title: "Your budget, explained", body: "Groceries is the big lever this month." },
       follow_ups: [ { title: "Import your credit card statement", due_on: nil } ])

    run = perform

    assert run.done?, run.error
    groceries = @user.budget_categories.find_by!(name: "Groceries")
    assert_equal 52_000, groceries.monthly_target_cents
    assert_equal "needs", groceries.group
    assert_equal "tool", groceries.target_set_by

    note = run.items.grep(Note).sole
    assert_match(/Groceries: 520/, note.body)
    assert_match(/your 3-month average is 480/, note.body)
    assert_match(/imported spending/, note.body, "the footer names what the numbers came from")
    assert_equal [ sections(:budget) ], note.sections
    assert_equal 1, run.items.grep(Task).size

    assert_requested(:post, ENDPOINT) do |request|
      # Code aggregates; the model never sees raw transaction rows.
      request.body.include?("Monthly average spending by category") &&
        request.body.include?("Recurring charges") &&
        !request.body.include?("occurred_on")
    end
  end

  test "a hand-set target survives a re-run; a tool-set one is tuned" do
    hand = @user.budget_categories.create!(name: "Groceries", group: "needs",
      monthly_target_cents: 60_000, target_set_by: "user")
    tool_set = @user.budget_categories.create!(name: "Dining out", group: "wants",
      monthly_target_cents: 15_000, target_set_by: "tool")

    stub_budget(categories: [
      { name: "groceries", group: "wants", monthly_target: 300, why: "trimmed" },
      { name: "Dining out", group: "wants", monthly_target: 90, why: "trimmed" }
    ])

    perform

    assert_equal 60_000, hand.reload.monthly_target_cents, "the user's own number is never overwritten"
    assert_equal "needs", hand.group
    assert_equal 9_000, tool_set.reload.monthly_target_cents
  end

  test "the intake path works with no ledger at all and says so" do
    stub_budget(categories: [ { name: "Housing", group: "needs", monthly_target: 1200, why: "you told us" } ],
      summary: { title: "A starting point", body: "Nothing imported yet, so these are estimates." })

    run = perform(inputs: { "take_home" => "about 2800", "housing" => "1200", "situation" => "new baby" })

    assert run.done?, run.error
    assert_equal 120_000, @user.budget_categories.sole.monthly_target_cents
    note = run.items.grep(Note).sole
    assert_match(/no imported spending yet/, note.body)
    assert_requested(:post, ENDPOINT) { |request| request.body.include?("new baby") && request.body.include?("2800") }
  end

  test "malformed envelopes are dropped, never stored" do
    stub_budget(categories: [
      { name: "Groceries", group: "needs", monthly_target: 400, why: "ok" },
      { name: "Nonsense", group: "needs", monthly_target: "a lot" },        # non-numeric
      { name: "Negative", group: "needs", monthly_target: -50 },            # negative
      { name: "Absurd", group: "needs", monthly_target: 99_999_999_999 },   # past the ceiling
      { name: "GROCERIES", group: "wants", monthly_target: 900 },           # duplicate name
      { group: "needs", monthly_target: 100 }                               # nameless
    ])

    perform

    assert_equal %w[ Groceries ], @user.budget_categories.pluck(:name)
    assert_equal 40_000, @user.budget_categories.sole.monthly_target_cents
  end

  test "an unusable group falls back rather than failing the run" do
    stub_budget(categories: [ { name: "Groceries", group: "vibes", monthly_target: 400 } ])

    assert perform.done?
    assert_equal "needs", @user.budget_categories.sole.group
  end

  test "a budget with no usable envelopes fails the run with a friendly message" do
    stub_budget(categories: [])

    run = perform

    assert run.failed?
    assert_match(/didn't return a budget/, run.error)
  end

  test "re-running shows the model the current envelopes and this month's actuals" do
    category = @user.budget_categories.create!(name: "Groceries", group: "needs",
      monthly_target_cents: 50_000, target_set_by: "user")
    spend("SAFEWAY", 20_000, category: category)

    stub_budget(categories: [ { name: "Groceries", group: "needs", monthly_target: 500, why: "held" } ])
    perform

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("already has these envelopes") &&
        request.body.include?("set by the user")
    end
  end

  private
    def perform(inputs: {})
      run = @user.tool_runs.create!(tool_slug: "build_my_budget", inputs: inputs)
      ToolRunJob.perform_now(run)
      run.reload
    end

    def stub_budget(categories:, summary: { title: "Budget", body: "Here it is." }, follow_ups: [])
      stub_request(:post, ENDPOINT).to_return(status: 200, body: {
        choices: [ { message: { content: {
          budget: { categories: categories }, summary: summary, follow_ups: follow_ups
        }.to_json } } ]
      }.to_json)
    end

    def spend(descriptor, cents, on: Date.current, category: nil)
      SpendingTransaction.create!(
        user_id: @user.id, spending_account_id: @account.id,
        occurred_on: on, amount_cents: -cents, descriptor: descriptor,
        merchant: Spending::Normalize.merchant(descriptor),
        budget_category_id: category&.id,
        fingerprint: "test-#{SecureRandom.hex(6)}", source: "statement")
    end
end
