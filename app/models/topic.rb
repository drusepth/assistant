# A node in a subject's curriculum tree (D-education-spine): a strand when
# it has children, a masterable leaf otherwise. Mastery is a state machine
# advanced only by evidence (D-mastery-evidence) — never by seat time — and
# honest enough to go backwards: `rusty` is where mastered decays when
# reviews lapse.
class Topic < ApplicationRecord
  belongs_to :subject, touch: true
  belongs_to :parent, class_name: "Topic", optional: true
  belongs_to :goal, optional: true
  has_many :children, -> { order(:position) }, class_name: "Topic", foreign_key: :parent_id,
    dependent: :destroy, inverse_of: :parent
  has_many :review_items, dependent: :destroy

  enum :mastery, { unseen: 0, learning: 1, practicing: 2, mastered: 3, rusty: 4 }, default: :unseen

  EVIDENCE = %w[ quiz tutor teach_back self_marked placement ].freeze

  validates :title, presence: true
  validates :mastery_evidence, inclusion: { in: EVIDENCE }, allow_nil: true

  delegate :user, to: :subject

  scope :ordered, -> { order(:position, :id) }

  def strand? = children.loaded? ? children.any? : children.exists?

  def leaf? = !strand?

  # The one door mastery moves through: stamps the evidence and, on reaching
  # mastered, the date. Demotion to rusty keeps both — the history is the
  # record (D-learning-record).
  def advance!(to:, evidence:)
    update!(
      mastery: to,
      mastery_evidence: evidence,
      mastered_on: to.to_s == "mastered" ? Date.current : mastered_on
    )
  end

  # Re-earning green after decay is the same evidence path.
  def shore_up!(evidence: "quiz")
    advance!(to: :mastered, evidence: evidence) if rusty?
  end
end
