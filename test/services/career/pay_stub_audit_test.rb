require "test_helper"

# The code-side arithmetic (docs/CAREER.md §3.3) shared by the stub-check
# tool and the stub-anomaly watcher — a wage-theft signal never depends on
# model behavior.
class Career::PayStubAuditTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "gross short of hours × rate is a concerning finding" do
    audit = audit_for(rate: "19", hours: "80", gross: "1400")

    assert audit.concerning?
    assert_match(/\$120\.00 missing/, audit.concerning_findings.sole)
  end

  test "overtime hours are paid at 1.5x before the gross is judged" do
    audit = audit_for(rate: "20", hours: "40", overtime_hours: "4", gross: "920")

    assert_not audit.concerning?, "40×20 + 4×30 = 920 — nothing missing"
  end

  test "a one-week stub over 40 hours with no overtime line is concerning" do
    audit = audit_for(rate: "18", hours: "46", gross: "828",
      period_start: "2026-03-01", period_end: "2026-03-07")

    assert audit.concerning?
    assert_match(/no overtime line/, audit.concerning_findings.sole)
  end

  test "a biweekly stub at 80 hours is not an overtime flag" do
    audit = audit_for(rate: "18", hours: "80", gross: "1440",
      period_start: "2026-03-01", period_end: "2026-03-14")

    assert_not audit.concerning?
  end

  test "a rate drop against the previous stub is concerning" do
    stub_document("Old stub", rate: "21", pay_date: "2026-03-15")
    audit = audit_for(rate: "19", pay_date: "2026-04-15")

    assert audit.concerning?
    assert_match(/rate dropped/, audit.concerning_findings.sole)
  end

  test "a new deduction is a finding but not an alarm" do
    stub_document("Old stub", rate: "19", pay_date: "2026-03-15",
      deductions: [ { label: "Federal income tax", amount: "$120" } ])
    audit = audit_for(rate: "19", pay_date: "2026-04-15",
      deductions: [ { label: "Federal income tax", amount: "$120" },
                    { label: "Wellness program", amount: "$25" } ])

    assert_not audit.concerning?
    assert_match(/New deduction since the last stub: Wellness program \(\$25\.00\)/, audit.findings.sole)
  end

  test "a clean stub has nothing to say" do
    audit = audit_for(rate: "19", hours: "80", gross: "1520")

    assert_empty audit.findings
    assert_not audit.concerning?
  end

  test "stubs from a different employer never compare" do
    stub_document("Old job", rate: "25", pay_date: "2026-03-15", employer: "Acme")
    audit = audit_for(rate: "19", pay_date: "2026-04-15", employer: "Bravo")

    assert_not audit.concerning?, "a pay cut you took by changing jobs is not an anomaly"
  end

  private
    def stub_document(title, **facts)
      @user.documents.create!(
        title: title,
        extracted_facts: { "pay_stub" => facts.map { |k, v| [ k.to_s, v.is_a?(Array) ? v.map { |d| d.transform_keys(&:to_s) } : v ] }.to_h }
      )
    end

    def audit_for(**facts)
      Career::PayStubAudit.new(Career::PayStub.for(stub_document("Current stub", **facts)))
    end
end
