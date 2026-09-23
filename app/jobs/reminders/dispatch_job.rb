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
    return advance(reminder) if reminder.standing?

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

    deliver(reminder)
  end

  private
    # A standing reminder (D-standing-reminders) is re-armed, not retired.
    # The claim and the re-arm are one conditional statement keyed on the
    # moment this job loaded, so there is no window between "sent" and
    # "advanced" and a second job for the same tick — or a user edit that
    # landed in between — finds nothing to claim. The next moment is the
    # first occurrence after *now*, so a box that was off for three
    # Thursdays pings about none of them and the series survives.
    def advance(reminder)
      now = Time.current
      next_at = reminder.next_deliver_at(after: now)
      # An UNTIL has passed: this was the last one. Retire it the one-shot way.
      changes = next_at ? { deliver_at: next_at, last_delivered_at: now } : { delivered_at: now, last_delivered_at: now }

      return if Reminder.pending.where(id: reminder.id, deliver_at: reminder.deliver_at).update_all(changes).zero?
      # A routine (D-task-routines): the chore comes back onto the board on
      # its day, missed ping or not — the chore is owed even when a late
      # notification about it would be noise.
      reminder.subject.come_round! if reminder.subject.is_a?(Task)
      # Missed by more than a day: the series is already re-armed above, and
      # the same judgment as a stale one-shot says this ping is noise.
      return if reminder.stale?(now)

      deliver(reminder)
    end

    def deliver(reminder)
      Notifications::Deliver.new(reminder.user, titles: [ reminder.body ], summary: reminder.message).call
    end
end
