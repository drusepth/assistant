# One retrieval prompt (D-review-scheduler): minted by quizzes, tutor
# session mining, or by hand, attached to the topic it evidences and to the
# learner directly (queue queries never join through the tree). The FSRS
# memory-state columns are written only by Reviews::Scheduler — the
# schedule is arithmetic, the model only writes and grades cards.
class ReviewItem < ApplicationRecord
  belongs_to :user
  belongs_to :topic

  enum :kind, { flash: 0, free_response: 1, do_this: 2 }, default: :flash
  enum :state, { fresh: 0, learning: 1, review: 2, relearning: 3 }, default: :fresh

  validates :prompt, presence: true

  scope :due, -> { where(due_at: ..Time.current).or(where(due_at: nil)) }
  # Interleaving by construction: overdue-first, then id keeps the shuffle
  # stable within a session while adjacent cards come from wherever they're
  # due, not from one subject's block.
  scope :queue_order, -> { order(Arel.sql("due_at IS NOT NULL, due_at ASC, id ASC")) }

  def due? = due_at.nil? || due_at <= Time.current
end
