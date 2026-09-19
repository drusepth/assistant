# The model's judgment that a happening is for this person (D-event-radar):
# which of their targets it matched — a hobby lens, the interest brief
# (`household`) or the causes brief (`causes`) — and one sentence saying
# why. `reason` is display, never logic: nothing reads it back.
#
# A rejected match is a tombstone rather than a deletion, exactly as a
# rejected story routing is (D-story-matching): it keeps a re-read from
# putting the row back, retires any suggestion built on it, and becomes an
# example in the next batch's prompt — which is the entire correction loop,
# since there are no rules here to correct.
class HappeningMatch < ApplicationRecord
  belongs_to :happening
  belongs_to :section, optional: true

  HOUSEHOLD = "household".freeze
  CAUSES = "causes".freeze

  enum :source, { model: "model", hand: "hand" }, default: :model, prefix: true

  scope :live, -> { where(rejected_at: nil) }
  scope :rejected, -> { where.not(rejected_at: nil) }
  scope :for_target, ->(key) { where(target: key) }

  validates :target, presence: true
  validates :reason, length: { maximum: 200 }
  validates :happening_id, uniqueness: { scope: :target }

  def rejected? = rejected_at.present?
  def reject! = update!(rejected_at: Time.current)
  def restore! = update!(rejected_at: nil)
  def because = reason.presence

  def household? = target == HOUSEHOLD
  def causes? = target == CAUSES
  def subject? = target.start_with?("subject:")

  def subject = subject? ? Subject.find_by(id: target.delete_prefix("subject:")) : nil

  # What the chip on the row says.
  def label
    return "For you" if household?
    return "A cause" if causes?
    return "Learning #{subject&.title || "something"}" if subject?

    section&.name
  end
end
