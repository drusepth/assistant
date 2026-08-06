class Event < ApplicationRecord
  include Visible
  include Sectionable

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
end
