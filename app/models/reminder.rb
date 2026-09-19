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

  # What the Repeat picker offers (D-standing-reminders): the Google Calendar
  # list, composed into an explicit RRULE from the picked day so the next
  # occurrence is a pure function of the rule and the current one. Weekly
  # keys take the weekday chips; the rest read the picked date.
  REPEAT_OPTIONS = {
    "none" => "Doesn't repeat",
    "daily" => "Every day",
    "weekdays" => "Every weekday",
    "weekly" => "Every week",
    "biweekly" => "Every 2 weeks",
    "monthly" => "Every month",
    "yearly" => "Every year"
  }.freeze
  WEEKLY_REPEATS = %w[ weekly biweekly ].freeze

  belongs_to :user
  belongs_to :subject, polymorphic: true, optional: true

  # Virtual date/time parts backing the forms, the same shape Event uses
  # (D16): a day plus a time, never a raw datetime typed by hand.
  attribute :deliver_on, :date
  attribute :deliver_time, :string
  # The picker's parts: a REPEAT_OPTIONS key, the chosen weekday codes for
  # the weekly keys, and an optional last day. Composed into `rule` before
  # validation.
  attribute :repeat, :string
  attribute :repeat_until, :date

  scope :pending, -> { where(delivered_at: nil) }
  scope :upcoming, -> { pending.order(:deliver_at) }
  scope :relative, -> { where.not(lead_minutes: nil) }
  scope :standing, -> { where.not(rule: nil) }

  before_validation :inherit_body
  before_validation :apply_lead_time
  before_validation :compose_deliver_at
  before_validation :compose_rule
  before_validation :align_to_rule

  validates :body, presence: true, length: { maximum: MAX_BODY }
  validates :deliver_at, presence: true
  validates :subject_type, inclusion: { in: SUBJECT_TYPES }, allow_nil: true
  validate :subject_is_the_users_own
  validate :rule_is_standing_safe
  validate :end_follows_start
  # A standing reminder never fails this: `align_to_rule` has already moved
  # it to the first occurrence still ahead.
  validate :moment_has_not_passed, if: -> { !standing? && deliver_at_changed? }

  def self.due(now = Time.current) = pending.where(deliver_at: ..now)

  def relative? = lead_minutes.present?

  # A reminder with a rule: `deliver_at` is the next occurrence, and
  # delivering advances it rather than retiring the row.
  def standing? = rule.present?

  def recurrence = Recurrence::Rule.parse(rule)

  # The first occurrence strictly after `after`, walking forward from the
  # moment currently armed — so a series that missed three Thursdays lands
  # on the coming one and never on the missed ones. Nil once the rule has
  # run out (an UNTIL passed).
  def next_deliver_at(after: Time.current)
    recurrence.next_after(after, current: local_deliver_at)
  end

  # "weekly on Thursday" — nil for a one-shot.
  def cadence = recurrence&.describe

  def stale?(now = Time.current) = deliver_at < (now - STALE_AFTER)

  # The picker's reading of the stored rule, so an edit form opens on what
  # was chosen; a value assigned from the form wins until saved.
  def repeat
    super || self.class.repeat_key_for(recurrence)
  end

  def repeat_days = @repeat_days || recurrence&.weekdays || []

  def repeat_until
    super || recurrence&.until_date
  end

  def repeat_days=(codes)
    @repeat_days = Array(codes).map { |code| code.to_s.strip.upcase }.select { |code| Recurrence::Rule::WEEKDAYS.key?(code) }
  end

  def self.repeat_key_for(recurrence)
    return "none" if recurrence.nil?

    case recurrence.freq
    when "DAILY" then "daily"
    when "WEEKLY"
      if recurrence.interval == 2 then "biweekly"
      elsif recurrence.weekdays.sort == Recurrence::Rule::WORKDAYS.sort then "weekdays"
      else "weekly"
      end
    when "MONTHLY" then "monthly"
    when "YEARLY" then "yearly"
    end
  end

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
    # Only when a form supplied the parts: a save that touched neither (the
    # dispatcher retiring a row, a repeat changed on its own) leaves the
    # stored moment exactly as it is, seconds included.
    def compose_deliver_at
      return if relative? || deliver_on.blank?
      return unless deliver_on_changed? || deliver_time_changed?

      date = deliver_on
      hour, minute = deliver_time.presence&.split(":")
      self.deliver_at = zone.local(date.year, date.month, date.day, (hour || DEFAULT_HOUR).to_i, minute.to_i)
    end

    # The picker's key becomes RRULE text. A key the form never sent (the
    # lead-time form, a resync) leaves the stored rule alone; "none" clears
    # it. Written explicitly — BYDAY, BYMONTHDAY — so the row needs no anchor
    # beyond the moment it fires next.
    def compose_rule
      key = self[:repeat]
      return if key.nil?

      text = case key
      when "none" then nil
      when "daily" then "FREQ=DAILY"
      when "weekdays" then "FREQ=WEEKLY;BYDAY=#{Recurrence::Rule::WORKDAYS.join(',')}"
      when "weekly" then "FREQ=WEEKLY;BYDAY=#{weekly_days}"
      when "biweekly" then "FREQ=WEEKLY;INTERVAL=2;BYDAY=#{weekly_days}"
      when "monthly" then deliver_on && "FREQ=MONTHLY;BYMONTHDAY=#{deliver_on.day}"
      when "yearly" then "FREQ=YEARLY"
      else key
      end
      # The last day is inclusive: UNTIL as a date runs to the end of it.
      text = "#{text};UNTIL=#{repeat_until.strftime('%Y%m%d')}" if text && repeat_until
      self.rule = text
    end

    def end_follows_start
      return unless standing? && repeat_until && deliver_on && repeat_until < deliver_on

      errors.add(:base, "That end date is before the first reminder.")
    end

    # The chips, or the picked day's weekday when none were touched.
    def weekly_days
      codes = repeat_days.presence || [ deliver_on && Recurrence::Rule::WEEKDAY_CODES[deliver_on.wday] ].compact
      codes.sort_by { |code| Recurrence::Rule::WEEKDAYS[code] }.join(",")
    end

    # The picked moment is where the series *starts*, not necessarily an
    # occurrence: "every week on Thursday" chosen on a Saturday means the
    # coming Thursday, and one chosen at 9pm for 8pm tonight means next
    # week's — never an error, never a first ping on the wrong day.
    def align_to_rule
      return unless standing? && deliver_at.present? && recurrence.standing?

      self.deliver_at = next_deliver_at(after: Time.current)
    end

    def rule_is_standing_safe
      return if rule.blank?

      if relative?
        errors.add(:base, "A repeating reminder needs its own time — pick one instead of a lead time.")
      elsif !recurrence.standing?
        errors.add(:base, "That repeat isn't one we understand.")
      elsif deliver_at.blank?
        errors.add(:base, "That repeat has already run out.")
      end
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
