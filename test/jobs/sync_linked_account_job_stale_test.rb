require "test_helper"

# The E0 recurring fan-out: every few minutes, enqueue a sync for each
# link whose registry cadence has elapsed. Cadence logic itself is tested
# on the model (sync_due?); this covers the fan-out wiring.
class SyncLinkedAccountJobStaleTest < ActiveJob::TestCase
  test "sync_stale enqueues only links that are due" do
    contacts = linked_accounts(:alice_contacts)
    calendar = linked_accounts(:alice_calendar)
    contacts.update!(synced_at: 2.hours.ago)
    calendar.update!(synced_at: 5.minutes.ago)
    linked_accounts(:alice_email).update!(synced_at: 1.minute.ago)

    SyncLinkedAccountJob.sync_stale

    assert_enqueued_with(job: SyncLinkedAccountJob, args: [ contacts ])
    assert_no_enqueued_jobs(only: SyncLinkedAccountJob) { } # already enqueued above; nothing further
    enqueued = enqueued_jobs.select { |job| job["job_class"] == "SyncLinkedAccountJob" }
    assert_equal 1, enqueued.size, "only the overdue link should be enqueued"
  end

  test "a paused link is skipped even when triggered directly" do
    contacts = linked_accounts(:alice_contacts)
    contacts.update!(settings: { "paused" => true }, synced_at: nil)

    SyncLinkedAccountJob.perform_now(contacts)

    assert_nil contacts.reload.synced_at, "a paused link must not sync"
  end
end
