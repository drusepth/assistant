require "test_helper"

# The coach pair (D-money-coach, docs/MONEY.md §5): the chat whose one hard
# guardrail is code, and the review whose every number arrived in its input.
class MoneyCoachToolsTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @account = @user.spending_accounts.create!(name: "Checking", kind: "checking")
    @groceries = @user.budget_categories.create!(name: "Groceries", group: "needs", monthly_target_cents: 50_000)
    @fun = @user.budget_categories.create!(name: "Fun money", group: "wants", monthly_target_cents: 10_000)
  end

  # ── money_coach ──────────────────────────────────────────────────────

  test "the not-an-advisor notice opens every session and never reaches the model" do
    spend(@groceries, 20_000)
    stub_chat("Hey — what's on your mind?")

    run = start_chat

    assert run.done?, "a chat run is live, not finished"
    notice = run.tool_run_messages.find_by!(role: "notice")
    assert_match(/not a licensed financial advisor/, notice.content)
    assert_match(/nonprofit credit counseling/, notice.content)

    assert_requested(:post, ENDPOINT) { |request| !request.body.include?("not a licensed financial advisor") }
  end

  test "the coach reasons from the budget snapshot, not raw transactions" do
    spend(@groceries, 47_000)
    spend(@fun, 3_000)
    stub_chat("Groceries is running warm this month.")

    start_chat

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Groceries: 470 USD of 500 USD") &&
        request.body.include?("30 USD left") &&
        !request.body.include?("SAFEWAY")
    end
  end

  test "an hourly rate is offered only when the comp timeline states one" do
    stub_chat("Hi.")
    start_chat
    assert_requested(:post, ENDPOINT) { |request| !request.body.include?("hours of work") }

    Career::CompChange.log!(user: @user, summary: "Raise: $19 → $21/hr")
    stub_chat("Hi again.")
    start_chat

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("21") && request.body.include?("hours of work")
    end
  end

  test "a chosen envelope and past recaps ride along as context" do
    previous = @user.tool_runs.create!(tool_slug: "money_coach", inputs: {}, status: :done)
    note = @user.notes.create!(title: "Decided to wait on the espresso machine", body: "Revisit in March.")
    previous.tool_run_items.create!(item: note)

    stub_chat("Let's look at Fun money.")
    start_chat(inputs: { "category_id" => @fun.id.to_s, "about" => "a $400 espresso machine" })

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("The envelope they came here about: Fun money") &&
        request.body.include?("espresso machine") &&
        request.body.include?("Decided to wait")
    end
  end

  test "a recap lands one filed Note and nothing else" do
    stub_chat("Hi.")
    run = start_chat
    run.tool_run_messages.create!(role: :user, content: "Talked myself out of it.")

    stub_request(:post, ENDPOINT).to_return(status: 200, body: {
      choices: [ { message: { content: {
        recap: { title: "Decided to wait on the espresso machine", body: "Revisit in March." }
      }.to_json } } ]
    }.to_json)
    ChatRecapJob.perform_now(run)

    note = run.reload.items.grep(Note).sole
    assert_equal "Decided to wait on the espresso machine", note.title
    assert_equal %w[ budget money ], note.sections.map(&:slug).sort
    assert_equal 0, run.items.grep(Task).size, "a chat never auto-writes anything else"
  end

  # ── spending_review ──────────────────────────────────────────────────

  test "the review narrates code-computed numbers and routes its cuts" do
    last_month = Date.current.prev_month.beginning_of_month
    spend(@groceries, 62_000, on: last_month)
    3.times { |i| spend(@fun, 1_599, on: last_month - (i * 30), descriptor: "NETFLIX.COM") }

    stub_review(
      review: { title: "Last month, plainly", body: "Groceries ran over; the rest held." },
      cuts: [
        { what: "Netflix", monthly_amount: 15.99, how: "Cancel it — you watched it twice.", tool: "cancel_subscription" },
        { what: "internet", monthly_amount: 20, how: "Call and ask for the promo rate.", tool: "negotiation_prep" },
        { what: "Vague", monthly_amount: "lots", tool: nil }
      ]
    )

    run = perform_review(month: last_month.strftime("%Y-%m"))

    assert run.done?, run.error
    note = run.items.grep(Note).sole
    assert_match(/Netflix: about 16 USD\/month/, note.body)
    assert_match(/internet: about 20 USD\/month/, note.body)
    assert_no_match(/Vague/, note.body, "a cut without a usable number is dropped")
    # Only the month under review is counted — the earlier Netflix charges
    # inform the recurring-charge aggregate but aren't July's transactions.
    assert_match(/Based on 2 transactions/, note.body)

    steps = run.output["next_tools"]
    assert_equal %w[ cancel_subscription negotiation_prep ], steps.map { |step| step["slug"] }
    assert_equal "Netflix", steps.first["inputs"]["service"]
    assert_match(/internet/, steps.second["inputs"]["scenario"])

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Groceries: 620 USD (target 500 USD)") && request.body.include?("Total spent")
    end
  end

  test "the review works on a thin ledger and says what it read" do
    stub_review(review: { title: "Not much to go on", body: "There's barely any data here yet." }, cuts: [])

    run = perform_review(month: Date.current.prev_month.strftime("%Y-%m"))

    assert run.done?, run.error
    assert_match(/Based on 0 transactions/, run.items.grep(Note).sole.body)
    assert_nil run.output["next_tools"]
  end

  test "an unusable month falls back to last month rather than failing" do
    stub_review(review: { title: "Review", body: "Body." }, cuts: [])

    run = perform_review(month: "not-a-month")

    assert run.done?, run.error
    assert_match(/#{Date.current.prev_month.strftime("%B %Y")}/, run.items.grep(Note).sole.body)
  end

  test "a review with no body fails the run with a friendly message" do
    stub_review(review: { title: "x", body: "" }, cuts: [])

    run = perform_review

    assert run.failed?
    assert_match(/didn't return a review/, run.error)
  end

  test "the month picker offers the months the ledger spans" do
    spend(@groceries, 1_000, on: Date.new(2026, 3, 4))
    spend(@groceries, 1_000, on: Date.new(2026, 5, 9))

    options = Tool::SpendingReview.month_options(@user)

    assert_equal [ "May 2026", "March 2026" ], options.map(&:first).first(2)
    assert_equal "2026-05", options.first.last
  end

  private
    def start_chat(inputs: {})
      run = @user.tool_runs.create!(tool_slug: "money_coach", inputs: inputs)
      ToolRunJob.perform_now(run)
      run.reload
    end

    def perform_review(month: Date.current.prev_month.strftime("%Y-%m"), focus: nil)
      run = @user.tool_runs.create!(tool_slug: "spending_review",
        inputs: { "month" => month, "focus" => focus }.compact)
      ToolRunJob.perform_now(run)
      run.reload
    end

    def stub_chat(content)
      stub_request(:post, ENDPOINT).to_return(status: 200, body: {
        choices: [ { message: { content: content } } ]
      }.to_json)
    end

    def stub_review(review:, cuts:, follow_ups: [])
      stub_request(:post, ENDPOINT).to_return(status: 200, body: {
        choices: [ { message: { content: {
          review: review, cuts: cuts, follow_ups: follow_ups
        }.to_json } } ]
      }.to_json)
    end

    def spend(category, cents, on: Date.current, descriptor: "SAFEWAY")
      SpendingTransaction.create!(
        user_id: @user.id, spending_account_id: @account.id,
        occurred_on: on, amount_cents: -cents, descriptor: descriptor,
        merchant: Spending::Normalize.merchant(descriptor),
        budget_category_id: category&.id,
        fingerprint: "t-#{SecureRandom.hex(6)}", source: "statement")
    end
end
