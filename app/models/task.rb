class Task < ApplicationRecord
  include Visible
  include Sectionable

  belongs_to :goal, optional: true

  validates :title, presence: true

  scope :open, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :due_by, ->(date) { where(due_on: ..date) }

  def completed? = completed_at.present?

  def complete!
    update!(completed_at: Time.current)
  end

  def reopen!
    update!(completed_at: nil)
  end
end
