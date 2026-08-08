require "test_helper"

class Spending::StatementImportTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = @user.spending_accounts.create!(name: "Checking", kind: "checking")
  end

  OFX = <<~OFX.freeze
    OFXHEADER:100
    DATA:OFXSGML
    <OFX>
    <BANKTRANLIST>
    <STMTTRN>
    <TRNTYPE>DEBIT
    <DTPOSTED>20260715120000[0:GMT]
    <TRNAMT>-45.67
    <FITID>2026071501
    <NAME>SAFEWAY STORE 1442
    </STMTTRN>
    <STMTTRN>
    <TRNTYPE>CREDIT
    <DTPOSTED>20260716
    <TRNAMT>1250.00
    <FITID>2026071602
    <NAME>ACME PAYROLL
    <MEMO>DIRECT DEP
    </STMTTRN>
    </BANKTRANLIST>
    </OFX>
  OFX

  test "imports OFX with signed cents, dates, and bank ids" do
    result = import(OFX, "statement.ofx")

    assert_nil result.error
    assert_equal 2, result.imported

    grocery = @account.transactions.find_by!(external_id: "2026071501")
    assert_equal Date.new(2026, 7, 15), grocery.occurred_on
    assert_equal(-4567, grocery.amount_cents)
    assert_includes grocery.merchant, "SAFEWAY"

    payroll = @account.transactions.find_by!(external_id: "2026071602")
    assert_equal 125_000, payroll.amount_cents
    assert_includes payroll.descriptor, "DIRECT DEP"
  end

  test "re-importing the same OFX is idempotent" do
    import(OFX, "statement.ofx")
    result = import(OFX, "statement.ofx")

    assert_equal 0, result.imported
    assert_equal 2, result.skipped
    assert_equal 2, @account.transactions.count
  end

  test "a removed transaction stays removed across re-imports" do
    import(OFX, "statement.ofx")
    @account.transactions.find_by!(external_id: "2026071501").remove_from_mirror!

    result = import(OFX, "statement.ofx")

    assert_equal 0, result.imported
    assert_nil @account.transactions.find_by(external_id: "2026071501")
    assert_equal 1, @account.transactions.count
  end

  test "identical same-day rows both import with distinct fingerprints" do
    csv = "Date,Description,Amount\n07/15/2026,COFFEE BAR,-4.50\n07/15/2026,COFFEE BAR,-4.50\n"
    @account.update!(csv_mapping: { "date" => "Date", "description" => "Description",
      "amount" => "Amount", "date_format" => "%m/%d/%Y", "sign" => "negative_out" })

    result = import(csv, "statement.csv")

    assert_equal 2, result.imported
    assert_equal 2, @account.transactions.distinct.count(:fingerprint)
  end

  test "a CSV from an unmapped account asks for a mapping" do
    result = import("Date,Description,Amount\n2026-07-01,STORE,-1.00\n", "statement.csv")

    assert_equal :mapping_needed, result.error
    assert_equal 0, @account.transactions.count
  end

  test "positive_out mapping flips the sign" do
    @account.update!(csv_mapping: { "date" => "Date", "description" => "Description",
      "amount" => "Amount", "date_format" => "%Y-%m-%d", "sign" => "positive_out" })

    import("Date,Description,Amount\n2026-07-01,STORE,12.50\n2026-07-02,REFUND,-3.00\n", "statement.csv")

    assert_equal(-1250, @account.transactions.find_by!(descriptor: "STORE").amount_cents)
    assert_equal 300, @account.transactions.find_by!(descriptor: "REFUND").amount_cents
  end

  test "separate debit and credit columns" do
    @account.update!(csv_mapping: { "date" => "Date", "description" => "Description",
      "debit" => "Money Out", "credit" => "Money In", "date_format" => "%d/%m/%Y" })

    import("Date,Description,Money Out,Money In\n15/07/2026,SHOP,20.00,\n16/07/2026,DEPOSIT,,50.00\n", "statement.csv")

    assert_equal(-2000, @account.transactions.find_by!(descriptor: "SHOP").amount_cents)
    assert_equal 5000, @account.transactions.find_by!(descriptor: "DEPOSIT").amount_cents
  end

  test "an unrecognizable file reports itself" do
    result = import("just some words", "notes.txt")
    assert_match(/doesn't look like a bank statement/, result.error)
  end

  test "opposite rows across accounts within the window pair as transfers" do
    credit = @user.spending_accounts.create!(name: "Card", kind: "credit")
    make_row(@account, Date.new(2026, 7, 10), -50_000, "PAYMENT TO CARD")
    make_row(credit, Date.new(2026, 7, 12), 50_000, "PAYMENT RECEIVED")
    make_row(@account, Date.new(2026, 7, 20), -50_000, "RENT") # outside window, stays spending

    Spending::Transfers.pair(@user)

    assert @account.transactions.find_by!(descriptor: "PAYMENT TO CARD").transfer?
    assert credit.transactions.find_by!(descriptor: "PAYMENT RECEIVED").transfer?
    assert_not @account.transactions.find_by!(descriptor: "RENT").transfer?
  end

  test "a human's transfer verdict is never overridden by pairing" do
    credit = @user.spending_accounts.create!(name: "Card", kind: "credit")
    out_row = make_row(@account, Date.new(2026, 7, 10), -50_000, "PAYMENT TO CARD")
    make_row(credit, Date.new(2026, 7, 11), 50_000, "PAYMENT RECEIVED")
    out_row.update!(transfer: false, transfer_set_by: "user")

    Spending::Transfers.pair(@user)

    assert_not out_row.reload.transfer?
  end

  private
    def import(content, filename)
      Spending::StatementImport.new(user: @user, account: @account,
        content: content, filename: filename).call
    end

    def make_row(account, date, cents, descriptor)
      SpendingTransaction.create!(
        user_id: @user.id, spending_account_id: account.id,
        occurred_on: date, amount_cents: cents, descriptor: descriptor,
        merchant: Spending::Normalize.merchant(descriptor),
        fingerprint: SpendingTransaction.fingerprint_for(account.id, date, cents, descriptor),
        source: "statement")
    end
end
