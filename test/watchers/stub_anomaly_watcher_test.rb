require "test_helper"

# The wage-theft tripwire: the newest stub failing the audit arithmetic
# earns one heads-up whose accept opens the stub-check tool on it.
class StubAnomalyWatcherTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a shorted stub earns one heads-up pointing at the stub-check tool" do
    stub = shorted_stub("April stub")

    suggestion = scan.sole
    assert suggestion.heads_up?
    assert_equal "stub_anomaly/doc:#{stub.id}", suggestion.fingerprint
    assert_includes suggestion.title, "April stub"
    assert_match(/missing/, suggestion.body)
    assert_equal({ "tool" => { "slug" => "check_pay_stub", "inputs" => { "document_id" => stub.id.to_s } } },
      suggestion.action)
    assert_equal [ sections(:career), sections(:money) ].to_set, suggestion.sections.to_set
  end

  test "only the newest stub is judged" do
    shorted_stub("Old short stub", pay_date: "2026-01-15")
    @user.documents.create!(title: "Clean newest stub",
      extracted_facts: { "pay_stub" => { "rate" => "19", "hours" => "80", "gross" => "1520", "pay_date" => "2026-04-15" } })

    assert_empty scan, "an old anomaly is stale news; the newest stub is fine"
  end

  test "a clean stub and a stubless user stay quiet" do
    assert_empty scan

    @user.documents.create!(title: "Clean stub",
      extracted_facts: { "pay_stub" => { "rate" => "19", "hours" => "80", "gross" => "1520" } })
    assert_empty scan
  end

  test "rescanning after a dismissal stays quiet — a stub's anomaly doesn't expire" do
    shorted_stub("April stub")
    scan.sole.dismiss!

    assert_no_difference "Suggestion.count" do
      Watcher::StubAnomaly.new(@user).scan
    end
  end

  private
    def shorted_stub(title, pay_date: "2026-04-15")
      @user.documents.create!(title: title,
        extracted_facts: { "pay_stub" => { "rate" => "19", "hours" => "80", "gross" => "1400", "pay_date" => pay_date } })
    end

    def scan
      Watcher::StubAnomaly.new(@user).scan
      @user.suggestions.pending.order(:id).to_a
    end
end
