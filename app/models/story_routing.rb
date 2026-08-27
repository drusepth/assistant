# One story the model put in a hobby its feed doesn't belong to
# (D-story-matching) — the exception to D-feed-reader's "an item's tags are
# its feed's tags", and the only kind of exception there is:
#
#   An item's tags are its feed's tags, **plus any exception recorded on the
#   item**. Nothing writes an exception without reading the story, and no
#   exception ever removes what the feed's tags gave.
#
# It lives in its own table rather than in `section_taggings` because an
# item is not a primitive (it is disposable, pruned on refresh, and becomes
# a Task or a Note when it matters), because a routing needs a `source` so a
# re-read can never overwrite something a human filed, and because routing
# churn does not belong in the table every section page joins against.
#
# `reason` is the model's own sentence about this story, shown on the row.
# It is display, never logic: nothing in the app reads it back.
#
# A rejected routing is a tombstone rather than a deletion. It stops the
# story being routed here again, and it becomes an example in the next
# batch's prompt — which is the entire correction loop, since there are no
# rules here to correct.
class StoryRouting < ApplicationRecord
  belongs_to :feed_item
  belongs_to :section

  enum :source, { model: "model", hand: "hand" }, default: :model, prefix: true

  scope :live, -> { where(rejected_at: nil) }
  scope :rejected, -> { where.not(rejected_at: nil) }
  scope :since, ->(time) { where(created_at: time..) }

  validates :reason, length: { maximum: 200 }

  def rejected? = rejected_at.present?

  def reject! = update!(rejected_at: Time.current)

  def because = reason.presence
end
