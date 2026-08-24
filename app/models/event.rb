class Event < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable
  include Remindable

  AUTO_SORT_JOB = CategorizeEventJob

  belongs_to :goal, optional: true

  validates :title, presence: true
  validates :starts_at, presence: true

  scope :upcoming, -> { where(starts_at: Time.current..).order(:starts_at) }
  scope :between, ->(range) { where(starts_at: range).order(:starts_at) }
  scope :overlapping, ->(range) {
    where("starts_at <= ? AND COALESCE(ends_at, starts_at) >= ?", range.end, range.begin).order(:starts_at)
  }

  def finished?
    reference = ends_at || starts_at
    all_day? ? reference.end_of_day.past? : reference.past?
  end

  def early_morning?
    !all_day? && starts_at.hour < 9
  end

  # All-day events start at midnight, so "an hour before" counted from
  # starts_at would ping at 11pm the night before. The day starts when the
  # person being reminded is awake.
  def remind_from
    return starts_at unless all_day?

    starts_at.in_time_zone(user.household.zone).change(hour: Remindable::DAY_START_HOUR)
  end

  # Virtual date/time parts backing the forms (D16): a day plus optional
  # times, instead of a raw datetime the user has to type. Leaving the start
  # time blank makes the event all-day — there is no separate checkbox.
  attribute :starts_date, :date
  attribute :starts_time, :string
  attribute :ends_time, :string

  before_validation :compose_schedule

  def starts_date = super || starts_at&.to_date
  def starts_time = super || (starts_at.strftime("%H:%M") if starts_at && !all_day?)
  def ends_time = super || (ends_at.strftime("%H:%M") if ends_at && !all_day?)

  %i[ starts_date starts_time ends_time ].each do |part|
    define_method("#{part}=") do |value|
      @schedule_edited = true
      super(value)
    end
  end

  private
    # Only composes when a form touched the virtual parts — direct writes to
    # starts_at/ends_at (auto-sorting, tests) pass through untouched.
    def compose_schedule
      return unless @schedule_edited
      return if starts_date.blank?

      if starts_time.present?
        self.starts_at = at_time(starts_time)
        self.ends_at = ends_time.present? ? at_time(ends_time) : nil
        self.all_day = false
      else
        self.starts_at = starts_date.in_time_zone
        self.ends_at = nil
        self.all_day = true
      end
    end

    def at_time(value)
      hour, minute = value.to_s.match(/\A(\d{1,2}):(\d{2})/)&.captures
      return starts_date.in_time_zone unless hour && hour.to_i < 24 && minute.to_i < 60

      starts_date.in_time_zone.change(hour: hour.to_i, min: minute.to_i)
    end
end
