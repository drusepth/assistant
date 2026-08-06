# Pulls contacts from a "contacts" linked account (D21's first consumer).
# Enqueued when the link is created and from its "Sync now" button; sync
# state lands on the link so Settings can show it.
class SyncContactsJob < ApplicationJob
  queue_as :default

  def perform(linked_account)
    result = People::CarddavSync.new(linked_account).call
    linked_account.update!(synced_at: Time.current, sync_error: result.error)
  rescue People::CarddavSync::Error => e
    linked_account.update!(sync_error: e.message)
  rescue StandardError
    # A bug, not a user-facing condition: record that the sync didn't land,
    # but let the error propagate to the job backend's log.
    linked_account.update!(sync_error: "Something went wrong during sync — try again.")
    raise
  end
end
