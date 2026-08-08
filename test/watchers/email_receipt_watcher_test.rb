require "test_helper"

# Receipts become ledger rows only by a click (docs/MONEY.md §2.1) — the
# mirror-to-mirror path, read deterministically with no model call.
class EmailReceiptWatcherTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = @user.spending_accounts.create!(name: "Checking", kind: "checking")
    @link = linked_accounts(:alice_email)
    @folder = EmailFolder.create!(user_id: @user.id, linked_account_id: @link.id,
      name: "INBOX", role: "inbox", uidvalidity: 1, backfilled_at: Time.current)
  end

  test "a labeled receipt becomes a suggestion whose accept logs the transaction" do
    receipt(subject: "Your order", body: "Thanks!\nOrder total: $42.99\n", from: "receipts@bluebottle.com")

    Watcher::EmailReceipt.new(@user).scan
    Watcher::EmailReceipt.new(@user).scan

    suggestion = @user.suggestions.where(watcher_slug: "email_receipt").sole
    assert_match(/Log 42.99 USD at BLUEBOTTLE\?/, suggestion.title)
    assert_equal "Log it", suggestion.accept_label
    assert_equal [ "money" ], suggestion.sections.map(&:slug)

    row = suggestion.accept!
    assert_equal(-4_299, row.amount_cents)
    assert_equal "BLUEBOTTLE", row.merchant
    assert_equal "email_receipt", row.source
    assert_equal "cash", row.spending_account.kind
  end

  test "an accepted receipt runs through the user's filing rules" do
    coffee = @user.budget_categories.create!(name: "Dining out", group: "wants")
    @user.spending_rules.create!(matcher: "bluebottle", budget_category: coffee)
    receipt(body: "Total: $8.50", from: "receipts@bluebottle.com")

    Watcher::EmailReceipt.new(@user).scan
    row = @user.suggestions.sole.accept!

    assert_equal coffee.id, row.reload.budget_category_id
  end

  test "mail that isn't a labeled receipt, or has no readable total, stays quiet" do
    receipt(body: "Total: $10.00", category: "newsletter")
    receipt(subject: "Shipped", body: "Your package is on its way.", from: "ship@store.com")

    Watcher::EmailReceipt.new(@user).scan

    assert_empty @user.suggestions
  end

  test "a receipt matching a transaction already imported stays quiet" do
    SpendingTransaction.create!(user_id: @user.id, spending_account_id: @account.id,
      occurred_on: Date.current, amount_cents: -4_299, descriptor: "BLUE BOTTLE",
      merchant: "BLUE BOTTLE", fingerprint: "t-#{SecureRandom.hex(4)}", source: "statement")
    receipt(body: "Order total: $42.99", from: "receipts@bluebottle.com")

    Watcher::EmailReceipt.new(@user).scan

    assert_empty @user.suggestions
  end

  test "no spending account means no receipt nudges at all" do
    @account.destroy!
    receipt(body: "Total: $42.99", from: "receipts@bluebottle.com")

    Watcher::EmailReceipt.new(@user).scan

    assert_empty @user.suggestions
  end

  test "an implausible total is a parse error, not a purchase" do
    receipt(body: "Total: $99,999.00", from: "receipts@bluebottle.com")

    Watcher::EmailReceipt.new(@user).scan

    assert_empty @user.suggestions
  end

  private
    def receipt(subject: "Your receipt", body: "Total: $1.00", from: "receipts@store.com", category: "receipt")
      message_id = "r-#{SecureRandom.hex(4)}@x"
      EmailMessage.create!(
        user_id: @user.id, linked_account_id: @link.id, email_folder: @folder,
        uid: (EmailMessage.maximum(:uid) || 0) + 1, message_id: message_id, thread_key: message_id,
        direction: "inbound", from_email: from, from_name: "Store",
        to_emails: [ "one@example.com" ], subject: subject, body_text: body,
        sent_at: 1.day.ago, triage: { "category" => category, "by" => "model" }, triaged_at: Time.current)
    end
end
