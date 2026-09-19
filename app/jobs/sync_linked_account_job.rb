# Pulls data in from a syncable linked account (D26): the provider's
# registry entry names the sync service (contacts → People::CarddavSync,
# calendar → Events::CaldavSync). Enqueued when the link is created and
# from its "Sync now" button; sync state lands on the link so Settings
# can show it.
class SyncLinkedAccountJob < ApplicationJob
  queue_as :default

  # Recurring background sync (email plan E0): the schedule fans out every
  # few minutes; each link's registry cadence (sync_every) decides whether
  # it's actually due, so email can poll faster than DAV without separate
  # schedules. Cheap by design — a handful of rows, in-Ruby filtering.
  def self.sync_stale
    LinkedAccount.find_each { |account| perform_later(account) if account.sync_due? }
  end

  def perform(linked_account)
    return if linked_account.paused?
    service = linked_account.sync_service or return
    result = service.new(linked_account).call
    linked_account.update!(synced_at: Time.current, sync_error: result.error)
    # A large backfill works in bounded batches (Email::ImapSync): when a
    # run reports there's more, chain the next batch immediately.
    self.class.perform_later(linked_account) if result.respond_to?(:more?) && result.more?
    # Live email arrivals head straight to triage (E2) — backfill never
    # does (the economics rule: history is browse-only, never alerted on).
    if result.respond_to?(:new_live_ids) && result.new_live_ids.present?
      Email::TriageJob.perform_later(linked_account, result.new_live_ids)
    end
  rescue Dav::Client::Error, Email::ImapClient::Error, Meetup::CalendarSync::Error, Eventbrite::OrdersSync::Error => e
    linked_account.update!(sync_error: e.message)
  rescue StandardError
    # A bug, not a user-facing condition: record that the sync didn't land,
    # but let the error propagate to the job backend's log.
    linked_account.update!(sync_error: "Something went wrong during sync — try again.")
    raise
  end
end
