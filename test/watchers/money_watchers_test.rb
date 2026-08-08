require "test_helper"

# The faithfulness watchers (docs/MONEY.md §4): deterministic SQL and
# arithmetic over the ledger, no model in any signal path, and no signal
# means no nudge.
class MoneyWatchersTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = @user.spending_accounts.create!(name: "Checking", kind: "checking")
  end

  # ── budget_pace ──────────────────────────────────────────────────────

  test "an envelope running ahead of the month nudges once, routed to the coach" do
    travel_to Date.new(2026, 6, 10) do # a third through June
      groceries = envelope("Groceries", 50_000)
      spend(46_000, category: groceries)

      Watcher::BudgetPace.new(@user).scan
      Watcher::BudgetPace.new(@user).scan # a re-scan must not speak twice

      suggestion = @user.suggestions.where(watcher_slug: "budget_pace").sole
      assert_match(/Groceries is at 460 USD of 500 USD, 20 days left/, suggestion.title)
      assert_equal "money_coach", suggestion.action.dig("tool", "slug")
      assert_equal groceries.id.to_s, suggestion.action.dig("tool", "inputs", "category_id")
      assert_equal "Talk it through", suggestion.accept_label
    end
  end

  test "on pace, no target, or too late in the month all stay silent" do
    travel_to Date.new(2026, 6, 10) do
      spend(20_000, category: envelope("Groceries", 50_000))  # on pace
      spend(9_000, category: envelope("Fun money", nil))      # no target, no meter
      Watcher::BudgetPace.new(@user).scan

      assert_empty @user.suggestions.where(watcher_slug: "budget_pace")
    end

    travel_to Date.new(2026, 6, 28) do # 2 days left — too late to steer
      spend(46_000, category: BudgetCategory.find_by!(name: "Groceries"))
      Watcher::BudgetPace.new(@user).scan

      assert_empty @user.suggestions.where(watcher_slug: "budget_pace")
    end
  end

  test "a new month is a new nudge" do
    groceries = envelope("Groceries", 50_000)

    travel_to Date.new(2026, 6, 10) do
      spend(46_000, category: groceries, on: Date.new(2026, 6, 5))
      Watcher::BudgetPace.new(@user).scan
    end
    travel_to Date.new(2026, 7, 10) do
      spend(46_000, category: groceries, on: Date.new(2026, 7, 5))
      Watcher::BudgetPace.new(@user).scan
    end

    assert_equal 2, @user.suggestions.where(watcher_slug: "budget_pace").count
  end

  # ── new_recurring_charge ─────────────────────────────────────────────

  test "three steady monthly charges from a new merchant surface as a subscription" do
    recurring("CALM", 1_299, months: 3)

    Watcher::NewRecurringCharge.new(@user).scan
    Watcher::NewRecurringCharge.new(@user).scan

    suggestion = @user.suggestions.where(watcher_slug: "new_recurring_charge").sole
    assert_match(/Looks like a new subscription: CALM, about 12.99 USD a month/, suggestion.title)
    assert_equal "File it", suggestion.accept_label
    assert_equal "Decide about CALM (12.99 USD/month)", suggestion.action.dig("task", "title")
    assert suggestion.action.dig("event", "starts_at").present?, "filing puts the renewal on the calendar"
  end

  test "irregular spending at the same merchant is not a subscription" do
    [ 0, 3, 9, 14 ].each_with_index { |days_ago, i| spend(2_000 + (i * 900), on: Date.current - days_ago, descriptor: "CORNER STORE") }

    Watcher::NewRecurringCharge.new(@user).scan

    assert_empty @user.suggestions.where(watcher_slug: "new_recurring_charge")
  end

  test "a long-standing subscription is not news" do
    recurring("NETFLIX", 1_599, months: 8)

    Watcher::NewRecurringCharge.new(@user).scan

    assert_empty @user.suggestions.where(watcher_slug: "new_recurring_charge")
  end

  # ── price_hike ───────────────────────────────────────────────────────

  test "a step up in a recurring charge routes to negotiation prep" do
    recurring("CITY INTERNET", 6_500, months: 4, starting: 30)
    spend(8_200, on: Date.current, descriptor: "CITY INTERNET")

    Watcher::PriceHike.new(@user).scan
    Watcher::PriceHike.new(@user).scan

    suggestion = @user.suggestions.where(watcher_slug: "price_hike").sole
    assert_match(/CITY INTERNET went from 65.00 USD to 82.00 USD/, suggestion.title)
    assert_match(/204.00 USD a year/, suggestion.body)
    assert_equal "negotiation_prep", suggestion.action.dig("tool", "slug")
    assert_match(/CITY INTERNET/, suggestion.action.dig("tool", "inputs", "scenario"))
  end

  test "cent-level jitter is not a price hike" do
    recurring("WATER UTILITY", 4_000, months: 4, starting: 30)
    spend(4_050, on: Date.current, descriptor: "WATER UTILITY")

    Watcher::PriceHike.new(@user).scan

    assert_empty @user.suggestions.where(watcher_slug: "price_hike")
  end

  test "a hiked charge is reported as a hike, not as a new subscription" do
    recurring("CITY INTERNET", 6_500, months: 3, starting: 30)
    spend(8_200, on: Date.current, descriptor: "CITY INTERNET")

    Watcher::NewRecurringCharge.new(@user).scan

    assert_empty @user.suggestions.where(watcher_slug: "new_recurring_charge")
  end

  # ── month_close ──────────────────────────────────────────────────────

  test "a month with activity offers its review, once" do
    spend(12_000, on: Date.current.prev_month.beginning_of_month + 3)

    Watcher::MonthClose.new(@user).scan
    Watcher::MonthClose.new(@user).scan

    suggestion = @user.suggestions.where(watcher_slug: "month_close").sole
    assert_match(/#{Date.current.prev_month.strftime("%B")} review is ready/, suggestion.title)
    assert_equal "spending_review", suggestion.action.dig("tool", "slug")
    assert_equal Date.current.prev_month.strftime("%Y-%m"), suggestion.action.dig("tool", "inputs", "month")
  end

  test "no ledger at all means silence from every money watcher" do
    envelope("Groceries", 50_000)

    Watcher::BudgetPace.new(@user).scan
    Watcher::NewRecurringCharge.new(@user).scan
    Watcher::PriceHike.new(@user).scan
    Watcher::MonthClose.new(@user).scan

    assert_empty @user.suggestions
  end

  test "watchers read only their own user's ledger" do
    their_account = users(:two).spending_accounts.create!(name: "Theirs", kind: "checking")
    3.times do |i|
      SpendingTransaction.create!(user_id: users(:two).id, spending_account_id: their_account.id,
        occurred_on: Date.current - (i * 30), amount_cents: -1_299, descriptor: "CALM", merchant: "CALM",
        fingerprint: "t-#{SecureRandom.hex(4)}", source: "statement")
    end

    Watcher::NewRecurringCharge.new(@user).scan

    assert_empty @user.suggestions
  end

  test "every money watcher is registered and section-tagged for the dials" do
    %w[ budget_pace new_recurring_charge price_hike month_close ].each do |slug|
      watcher = Watcher.find!(slug)
      assert watcher.section_slugs.any?, "#{slug} needs sections so the dials can reach it"
      assert (watcher.section_slugs - Section.pluck(:slug)).empty?, "#{slug} names a section that doesn't exist"
    end
  end

  private
    def envelope(name, target_cents)
      @user.budget_categories.create!(name: name, group: "needs", monthly_target_cents: target_cents)
    end

    # `starting` backs the whole series up so a later charge can land on
    # its own billing date rather than doubling up on the newest one.
    def recurring(descriptor, cents, months:, starting: 0)
      months.times { |i| spend(cents, on: Date.current - starting - (i * 30), descriptor: descriptor) }
    end

    def spend(cents, on: Date.current, category: nil, descriptor: "SAFEWAY")
      SpendingTransaction.create!(
        user_id: @user.id, spending_account_id: @account.id,
        occurred_on: on, amount_cents: -cents, descriptor: descriptor,
        merchant: Spending::Normalize.merchant(descriptor),
        budget_category_id: category&.id,
        fingerprint: "t-#{SecureRandom.hex(6)}", source: "statement")
    end
end
