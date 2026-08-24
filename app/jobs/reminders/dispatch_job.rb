# Fires user-armed reminders (D-reminders).
#
# Polling every few minutes rather than enqueueing a job at deliver_at: a
# reminder can be retimed by its event moving, edited, or deleted, and a
# job already sitting in the queue can't cleanly be un-queued — whereas a
# poll just reads the current truth each time. It is also the shape
# Email::DigestJob.dispatch_due already uses for the same reason.
class Reminders::DispatchJob < ApplicationJob
  queue_as :default

  # A reminder deleted between the fan-out and the run is not an error.
  discard_on ActiveJob::DeserializationError

  def self.dispatch_due
    Reminder.due.find_each { |reminder| perform_later(reminder) }
  end

  def perform(reminder)
    # Retire rather than deliver. A reminder surfacing a day late is noise,
    # and the box having been off is not a reason to ping about a meeting
    # that already happened.
    if reminder.stale?
      reminder.update!(delivered_at: Time.current)
      return
    end

    # Claim it before sending, atomically: the dispatcher runs on a timer,
    # so a job still queued at the next tick would otherwise be enqueued
    # twice — and on the SMS channels a double send costs real money.
    return if Reminder.pending.where(id: reminder.id).update_all(delivered_at: Time.current).zero?

    Notifications::Deliver.new(reminder.user, titles: [ reminder.body ], summary: reminder.message).call
  end
end
