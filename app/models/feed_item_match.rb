# One story that reached a hobby its feed doesn't belong to
# (D-story-matching) — the exception to D-feed-reader's "an item's tags are
# its feed's tags", and the only kind of exception there is:
#
#   An item's tags are its feed's tags, **plus any exception recorded on the
#   item**. Nothing writes an exception in bulk, and no exception ever
#   removes what the feed's tags gave.
#
# It lives in its own table rather than in `section_taggings` because an
# item is not a primitive (it is disposable, pruned on refresh, and becomes
# a Task or a Note when it matters), because a match needs a `source` so a
# rule edit can never overwrite something a human filed, and because match
# churn does not belong in the table every section page joins against.
#
# A rejected match is a tombstone rather than a deletion: it keeps the row
# from coming back on the next backfill, and it is the evidence
# `Feeds::Watchlists::Corrections` reads when it decides a term is wrong.
class FeedItemMatch < ApplicationRecord
  belongs_to :feed_item
  belongs_to :section

  enum :source, { match: "match", hand: "hand" }, default: :match, prefix: true

  scope :live, -> { where(rejected_at: nil) }
  scope :rejected, -> { where.not(rejected_at: nil) }
  scope :since, ->(time) { where(created_at: time..) }

  def rejected? = rejected_at.present?

  def reject! = update!(rejected_at: Time.current)

  # What to say when the row asks why it is here.
  def because = terms.first(2).join(", ").presence
end
