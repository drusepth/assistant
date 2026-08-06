class Task < ApplicationRecord
  include Visible
  include Sectionable

  belongs_to :goal, optional: true

  validates :title, presence: true

  scope :open, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :due_by, ->(date) { where(due_on: ..date) }

  def completed? = completed_at.present?

  def auto_sort_profile
    profile = user.household.model_profile
    profile if profile&.configured?
  end

  # Quick-added tasks get sorted by the household's model instead of a form;
  # tasks the user tagged by hand are left alone.
  def enqueue_auto_sort!
    return if sections.any?
    return unless auto_sort_profile

    CategorizeTaskJob.perform_later(self)
  end

  def complete!
    update!(completed_at: Time.current)
  end

  def reopen!
    update!(completed_at: nil)
  end
end
