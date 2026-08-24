# A time the user asked to be told something (D-reminders).
#
# Not a primitive: it owns no content of its own. It is a scheduled
# delivery over something that already exists — an Event, a Task — or over
# nothing at all, which is the "remind me to call the pharmacy at 4pm"
# case the feature exists for.
#
# The one rule that separates it from everything else that reaches a
# phone: a reminder is **user-armed**, so it ignores the D22 section dials
# entirely. Those dials say how chatty the *agent* may be; a person who
# set an alarm for 4pm has already answered that question. Same stance as
# the email plan's user-armed boomerang — no model in the path, no dial in
# the way.
class Reminder < ApplicationRecord
  # Only what a user can already see and edit. A reminder is delivery, not
  # a grant, so it never reaches past its owner's own items.
  SUBJECT_TYPES = %w[ Event Task ].freeze

  MAX_BODY = 200

  # A day picked with no time attached means "sometime that day", and 9am
  # is when the day starts for the person being reminded — midnight is a
  # notification nobody sees.
  DEFAULT_HOUR = 9

  # A reminder that missed its moment by more than this is stale: the box
  # was off, or the event it hung on was moved into the past. Surfacing it
  # late is worse than not surfacing it — it reads as the app being broken.
  STALE_AFTER = 1.day

  # What the pickers offer for an item that has a date of its own.
  # Absolute reminders are the ones with lead_minutes: nil.
  LEAD_OPTIONS = {
    0 => "At the time",
    15 => "15 minutes before",
    60 => "An hour before",
    180 => "3 hours before",
    1440 => "The day before",
    10080 => "A week before"
  }.freeze

  belongs_to :user
  belongs_to :subject, polymorphic: true, optional: true

  # Virtual date/time parts backing the forms, the same shape Event uses
  # (D16): a day plus a time, never a raw datetime typed by hand.
  attribute :deliver_on, :date
  attribute :deliver_time, :string

  scope :pending, -> { where(delivered_at: nil) }
  scope :upcoming, -> { pending.order(:deliver_at) }
  scope :relative, -> { where.not(lead_minutes: nil) }

  before_validation :inherit_body
  before_validation :apply_lead_time
  before_validation :compose_deliver_at

  validates :body, presence: true, length: { maximum: MAX_BODY }
  validates :deliver_at, presence: true
  validates :subject_type, inclusion: { in: SUBJECT_TYPES }, allow_nil: true
  validate :subject_is_the_users_own
  validate :moment_has_not_passed, on: :create

  def self.due(now = Time.current) = pending.where(deliver_at: ..now)

  def relative? = lead_minutes.present?

  def stale?(now = Time.current) = deliver_at < (now - STALE_AFTER)

  # Re-applies the lead time after the item it counts back from moved.
  # Without this, "an hour before" becomes a lie the moment an appointment
  # is rescheduled — the failure mode that makes people stop trusting
  # reminders altogether.
  def resync!
    return if delivered_at.present? || !relative?

    anchor = subject&.remind_from
    # The date it was counting back from is gone (a task's due date
    # cleared, say). There is no moment left to fire at.
    return destroy! if anchor.nil?

    update!(deliver_at: anchor - lead_minutes.minutes)
  end

  # What actually gets sent. Code-built from the user's own words and a
  # clock reading — never model prose, and never the subject's body (D22).
  def message
    phrase = subject_time_phrase

    phrase ? "Reminder: #{body} — #{phrase}" : "Reminder: #{body}"
  end

  def deliver_on = super || deliver_at&.in_time_zone(zone)&.to_date
  def deliver_time = super || deliver_at&.in_time_zone(zone)&.strftime("%H:%M")

  def local_deliver_at = deliver_at.in_time_zone(zone)

  private
    def zone = user&.household&.zone || Time.zone

    # "today at 4:00 PM" — only for a reminder that counts back from
    # something, where the interesting time is the item's, not the ping's.
    def subject_time_phrase
      return nil unless relative?

      anchor = subject&.remind_from
      return nil if anchor.nil?

      local = anchor.in_time_zone(zone)
      "#{day_word(local.to_date)} at #{local.strftime("%-l:%M %p")}"
    end

    def day_word(date)
      today = Time.current.in_time_zone(zone).to_date

      case date
      when today then "today"
      when today + 1 then "tomorrow"
      else date.strftime("%a %b %-d")
      end
    end

    def inherit_body
      return if body.present? || !subject.respond_to?(:title)

      self.body = subject.title.to_s.truncate(MAX_BODY)
    end

    def apply_lead_time
      return unless relative?

      anchor = subject&.remind_from
      self.deliver_at = anchor - lead_minutes.minutes if anchor
    end

    # An absolute reminder is composed in the household's zone, so "4pm"
    # means 4pm where the person lives rather than wherever the box is.
    # Recomposing an unedited reminder is a no-op: the readers above fall
    # back to the parts of the deliver_at already stored.
    def compose_deliver_at
      return if relative? || deliver_on.blank?

      date = deliver_on
      hour, minute = deliver_time.presence&.split(":")
      self.deliver_at = zone.local(date.year, date.month, date.day, (hour || DEFAULT_HOUR).to_i, minute.to_i)
    end

    def subject_is_the_users_own
      return if subject.blank?

      errors.add(:base, "That isn't yours to set a reminder on.") unless subject.user_id == user_id
    end

    def moment_has_not_passed
      return if deliver_at.blank?

      errors.add(:base, "That time has already passed.") if deliver_at.past?
    end
end
