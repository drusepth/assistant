class Event < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = CategorizeEventJob

  belongs_to :goal, optional: true

  validates :title, presence: true
  validates :starts_at, presence: true

  scope :upcoming, -> { where(starts_at: Time.current..).order(:starts_at) }
  scope :between, ->(range) { where(starts_at: range).order(:starts_at) }
end
