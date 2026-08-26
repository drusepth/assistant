# One durable line of the learning record (D-learning-record): who studied
# what, when, for how long. Written automatically by tutor and review
# sessions and by hand for offline work — kept in its own table because
# ToolRuns prune at 90 days and an hours log must not. Append-only in
# spirit; the record generators read it.
class StudyLog < ApplicationRecord
  belongs_to :user
  belongs_to :subject, optional: true
  belongs_to :topic, optional: true

  enum :activity, { tutor: 0, review: 1, lesson: 2, project: 3, other: 4 }, default: :other

  validates :on, presence: true
  validates :minutes, numericality: { greater_than: 0 }

  scope :between, ->(range) { where(on: range) }
end
