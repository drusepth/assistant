require "test_helper"

class AgentScanJobTest < ActiveJob::TestCase
  test "a scan wakes expired snoozes and lets every watcher look" do
    lens = Hobbies::Lens.find_or_create!("Guitar")
    lens.update_columns(created_at: 8.weeks.ago)

    AgentScanJob.perform_now(users(:one))

    suggestion = users(:one).suggestions.sole
    assert suggestion.pending?
    assert_equal "neglected_hobby", suggestion.watcher_slug

    suggestion.update!(status: :snoozed, snoozed_until: 1.minute.ago)
    AgentScanJob.perform_now(users(:one))
    assert suggestion.reload.pending?, "an expired snooze comes back instead of a duplicate"
    assert_equal 1, users(:one).suggestions.count
  end

  test "the fan-out enqueues one scan per user" do
    AgentScanFanOutJob.perform_now

    assert_enqueued_jobs User.count, only: AgentScanJob
  end
end
