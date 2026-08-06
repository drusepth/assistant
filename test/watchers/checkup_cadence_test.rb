require "test_helper"

# The first watcher, and the D20 contract in miniature: the signal is SQL,
# the emit is fingerprint-idempotent, and a dismissal stays dismissed.
class CheckupCadenceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "a year of health silence proposes a checkup with a concrete date payload" do
    assert_difference -> { users(:one).suggestions.count } do
      Watcher::CheckupCadence.new(users(:one)).scan
    end

    suggestion = users(:one).suggestions.sole
    assert suggestion.pending?
    assert_equal "checkup_cadence", suggestion.watcher_slug
    assert_equal "checkup_cadence:#{Date.current.year}", suggestion.fingerprint
    assert_equal [ sections(:health) ], suggestion.sections
    assert_equal "create_event", suggestion.action_type

    date = Date.iso8601(suggestion.action.dig("event", "date"))
    assert date > Date.current
    assert_not date.on_weekend?, "the payload date lands on a quiet weekday"
  end

  test "a recent or upcoming health event keeps it quiet" do
    event = users(:one).events.create!(title: "Physical", starts_at: 2.months.ago)
    event.sections << sections(:health)

    assert_no_difference -> { users(:one).suggestions.count } do
      Watcher::CheckupCadence.new(users(:one)).scan
    end
  end

  test "an unrelated event does not count as health signal" do
    event = users(:one).events.create!(title: "Concert", starts_at: 1.month.ago)
    event.sections << sections(:hobbies)

    assert_difference -> { users(:one).suggestions.count } do
      Watcher::CheckupCadence.new(users(:one)).scan
    end
  end

  test "re-scans never duplicate, and a dismissal stays dismissed this year" do
    Watcher::CheckupCadence.new(users(:one)).scan
    users(:one).suggestions.sole.dismiss!

    assert_no_difference -> { users(:one).suggestions.count } do
      Watcher::CheckupCadence.new(users(:one)).scan
      Watcher::CheckupCadence.new(users(:one)).scan
    end
  end

  test "the scan job runs every watcher for one user only" do
    assert_difference -> { users(:one).suggestions.count }, +1 do
      assert_no_difference -> { users(:two).suggestions.count } do
        AgentScanJob.perform_now(users(:one))
      end
    end
  end

  test "the fanout job enqueues a scan per user" do
    assert_enqueued_jobs User.count, only: AgentScanJob do
      AgentScanFanoutJob.perform_now
    end
  end
end
