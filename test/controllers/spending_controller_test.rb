require "test_helper"

class SpendingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @account = @user.spending_accounts.create!(name: "Checking", kind: "checking")
  end

  test "index shows only the signed-in user's ledger" do
    mine = make_row(@user, @account, "MY COFFEE SHOP")
    other_account = users(:two).spending_accounts.create!(name: "Their card", kind: "credit")
    make_row(users(:two), other_account, "THEIR SECRET STORE")

    get spending_path

    assert_response :success
    assert_match "MY COFFEE SHOP", response.body
    assert_no_match(/THEIR SECRET STORE/, response.body)
    assert mine.persisted?
  end

  test "quick log creates a manual row" do
    assert_difference -> { SpendingTransaction.where(user_id: @user.id).count } do
      post spending_transactions_path, params: { entry: "14.50 lunch" }
    end
    assert_redirected_to spending_path
  end

  test "recategorize with make_rule teaches a rule and applies it backwards" do
    category = @user.budget_categories.create!(name: "Dining out", group: "wants")
    row = make_row(@user, @account, "CHIPOTLE 0231")
    sibling = make_row(@user, @account, "CHIPOTLE 0499")

    patch spending_transaction_path(row), params: { budget_category_id: category.id, make_rule: "1" }

    assert_equal category.id, row.reload.budget_category_id
    assert_equal "user", row.categorized_by
    assert_equal category.id, sibling.reload.budget_category_id
    assert @user.spending_rules.exists?(matcher: row.merchant.downcase)
  end

  test "cannot touch another user's transaction" do
    other_account = users(:two).spending_accounts.create!(name: "Theirs", kind: "checking")
    row = make_row(users(:two), other_account, "THEIRS")

    patch spending_transaction_path(row), params: { budget_category_id: "" }
    assert_response :not_found
  end

  test "transfer toggle records the human's verdict" do
    row = make_row(@user, @account, "CARD PAYMENT")

    patch spending_transaction_path(row, transfer: "1")

    assert row.reload.transfer?
    assert_equal "user", row.transfer_set_by
  end

  test "destroy tombstones the row" do
    row = make_row(@user, @account, "MISTAKE")

    delete spending_transaction_path(row)

    assert_nil SpendingTransaction.find_by(id: row.id)
    assert SpendingTombstone.covers?(@account.id, row.fingerprint)
  end

  test "CSV import routes through mapping once, then imports one-click" do
    csv = "Date,Description,Amount\n07/15/2026,SAFEWAY,-45.67\n"

    post spending_imports_path, params: {
      spending_account_id: @account.id,
      file: fixture_upload(csv, "statement.csv") }

    assert_redirected_to(/spending\/import\/mapping/)
    document_id = Rack::Utils.parse_query(URI(response.location).query)["document_id"]

    post spending_import_apply_path, params: {
      document_id: document_id, account_id: @account.id,
      date: "Date", description: "Description", amount: "Amount",
      date_format: "%m/%d/%Y", sign: "negative_out" }

    assert_redirected_to spending_path
    assert_equal(-4567, @account.transactions.sole.amount_cents)
    assert_equal [ "money" ], Document.find(document_id).sections.map(&:slug)

    # The saved mapping makes the next import one step.
    post spending_imports_path, params: {
      spending_account_id: @account.id,
      file: fixture_upload("Date,Description,Amount\n07/16/2026,ALDI,-12.00\n", "next.csv") }

    assert_redirected_to spending_path
    assert_equal 2, @account.transactions.count
  end

  test "OFX imports in one step and files the statement in the vault" do
    ofx = "OFXHEADER:100\n<OFX><STMTTRN><DTPOSTED>20260715<TRNAMT>-9.99<FITID>x1<NAME>STORE</STMTTRN></OFX>"

    assert_difference -> { @user.documents.count } do
      post spending_imports_path, params: {
        spending_account_id: @account.id,
        file: fixture_upload(ofx, "statement.ofx") }
    end

    assert_redirected_to spending_path
    assert_equal(-999, @account.transactions.sole.amount_cents)
  end

  test "import can create the account inline" do
    post spending_imports_path, params: {
      new_account_name: "Fresh Card", new_account_kind: "credit",
      file: fixture_upload("OFXHEADER:100\n<OFX><STMTTRN><DTPOSTED>20260701<TRNAMT>-1.00<FITID>a</STMTTRN></OFX>", "s.ofx") }

    account = @user.spending_accounts.find_by!(name: "Fresh Card")
    assert_equal "credit", account.kind
    assert_equal 1, account.transactions.count
  end

  test "deleting an account purges its slice of the mirror" do
    row = make_row(@user, @account, "ROW")

    delete spending_account_path(@account)

    assert_nil SpendingTransaction.find_by(id: row.id)
  end

  private
    def make_row(user, account, descriptor)
      SpendingTransaction.create!(
        user_id: user.id, spending_account_id: account.id,
        occurred_on: Date.current, amount_cents: -1000, descriptor: descriptor,
        merchant: Spending::Normalize.merchant(descriptor),
        fingerprint: "test-#{SecureRandom.hex(6)}", source: "statement")
    end

    def fixture_upload(content, filename)
      Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: filename)
    end
end
