require "test_helper"

# The quiet pay cut, caught: flat comp timeline × the local CPI series →
# one yearly heads-up with the math shown. No timeline or no newer data →
# silence.
class RealTermsDriftWatcherTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "pay flat since 2021 with CPI up double digits earns the heads-up" do
    Career::CompChange.log!(user: @user, summary: "Raise: $17 → $19/hr", on: Date.new(2021, 6, 1))

    suggestion = scan.sole
    assert suggestion.heads_up?
    assert_equal "real_terms_drift/#{Date.current.year}", suggestion.fingerprint
    assert_match(/Prices are up ~\d+(\.\d+)?%/, suggestion.title)
    assert_match(/June 2021/, suggestion.body)
    assert_equal({ "tool" => { "slug" => "raise_case" } }, suggestion.action)
  end

  test "a change in the latest data year has nothing newer to compare — quiet" do
    Career::CompChange.log!(user: @user, summary: "Raise", on: Date.new(Datasets::Cpi.current.latest_year, 3, 1))

    assert_empty scan
  end

  test "no comp timeline means no claim" do
    assert_empty scan
  end

  private
    def scan
      Watcher::RealTermsDrift.new(@user).scan
      @user.suggestions.pending.order(:id).to_a
    end
end
