require "test_helper"

# The money kind (INTAKE_PLAN W4): a bill or receipt in the vault lands on
# the ledger through the same write the email-receipt suggestion uses.
class Landing::SpendingKindTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @context = Landing::Context.new(user: @user)
  end

  test "a paid bill lands on the Cash account as money out, categorized by the deterministic pass" do
    landing = Landing::Spending.new(@context)
    attrs = landing.validate("amount" => "$184.50", "occurred_on" => "2026-08-12", "merchant" => "Animal Hospital", "descriptor" => "Rex — vaccinations and exam")
    assert_equal "184.50", attrs["amount"]

    row = landing.land!(attrs, sections: [])
    assert_equal(-18_450, row.amount_cents)
    assert_equal "document", row.source
    assert_equal "Animal Hospital", row.merchant
    assert_equal Date.new(2026, 8, 12), row.occurred_on
    assert_equal "cash", row.spending_account.kind
    assert_equal row, landing.duplicate_of("amount" => "184.5", "occurred_on" => "2026-08-12", "merchant" => "whoever")
    assert_equal "$184.50 — Animal Hospital", landing.preview(attrs).title
  end

  test "the email-receipt suggestion lands through the same write" do
    suggestion = @user.suggestions.create!(watcher_slug: "email_receipts", fingerprint: "email_receipts/msg:1",
      title: "Log the Amazon receipt",
      action: { "spending" => { "amount_cents" => -2599, "merchant" => "AMAZON", "descriptor" => "Order 123", "occurred_on" => "2026-08-01" } })

    row = Array(suggestion.accept!).first
    assert_equal(-2599, row.amount_cents)
    assert_equal "email_receipt", row.source
    assert_predicate suggestion.reload, :accepted?
  end

  test "an amount that isn't a number sinks the entry" do
    assert_nil Landing::Spending.new(@context).validate("amount" => "free", "occurred_on" => "2026-08-12", "merchant" => "x")
  end
end
