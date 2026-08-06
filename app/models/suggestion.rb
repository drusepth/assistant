# The agent's only write surface (D20): a watcher noticed something and the
# app is speaking up. Nothing materializes until the user accepts — one
# explicit click — and the fingerprint (watcher + subject) keeps a dismissed
# nudge from reappearing on the next scan. Sectionable is what makes the
# Attend zone and the Dashboard feed plain in_section/unscoped queries.
# Suggestions are the owner's private surface (no Visible).
class Suggestion < ApplicationRecord
  include Sectionable

  belongs_to :user

  enum :kind, { nudge: "nudge", heads_up: "heads_up", insight: "insight" }, default: :nudge
  enum :status, { pending: "pending", accepted: "accepted", dismissed: "dismissed", snoozed: "snoozed" },
    default: :pending

  validates :watcher_slug, :fingerprint, :title, presence: true

  scope :attend, -> { pending.order(created_at: :desc) }

  # Accepting performs the action payload and returns what it created.
  def accept!
    item = perform_action
    update!(status: :accepted)
    item
  end

  def dismiss! = update!(status: :dismissed)

  def snooze!(until_time = 1.week.from_now)
    update!(status: :snoozed, snoozed_until: until_time)
  end

  # Expired snoozes return to pending — run at the top of each scan, so
  # "later" means later, not never.
  def self.wake_expired_snoozes!
    snoozed.where(snoozed_until: ..Time.current).update_all(status: "pending", snoozed_until: nil)
  end

  private
    # One action type so far (M3.1); more arrive with the watcher slate
    # (create this Task, run this Tool prefilled).
    def perform_action
      case action["type"]
      when "create_event"
        event = user.events.create!(title: action["title"].to_s, starts_at: action_date.in_time_zone, all_day: true)
        event.sections = Section.where(id: Array(action["section_ids"]))
        event
      else
        raise ActiveRecord::RecordInvalid.new(self)
      end
    end

    def action_date
      Date.iso8601(action["on"].to_s)
    rescue Date::Error
      Date.tomorrow
    end
end
