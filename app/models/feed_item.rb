# One entry from a followed feed (D-feed-reader). It is not a primitive and
# not Sectionable: an item's tags are its feed's tags, so filing happens
# once, at the subscription, and the river's hobby filter is a join rather
# than a per-item write. Items are disposable — the ones worth keeping
# become Tasks, Notes, or saves.
#
# The state here is deliberately the smallest set a reader needs: seen, and
# kept. No score, no vote, no rating — this is one person's reading list,
# and the river is in the order the world published it.
class FeedItem < ApplicationRecord
  belongs_to :feed
  has_one :user, through: :feed

  validates :guid, :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :saved, -> { where.not(saved_at: nil) }
  # The river's one order: newest first, by what the publisher said, and by
  # when we first saw it when they said nothing.
  scope :newest, -> { order(Arel.sql("COALESCE(published_at, feed_items.created_at) DESC"), id: :desc) }
  scope :recent, ->(within = 30.days) {
    where("COALESCE(published_at, feed_items.created_at) >= ?", within.ago)
  }

  def read? = read_at.present?
  def saved? = saved_at.present?

  def published_on = (published_at || created_at)

  def source_name = feed.display_title

  # Reading also stamps the feed (D-feed-reader): "does anybody still read
  # this?" decides how often we poll its publisher, and asking the items
  # that question once per feed per sweep was a query nobody needed.
  def mark_read!
    update!(read_at: Time.current)
    feed.touch_read!(read_at)
  end

  def mark_unread! = update!(read_at: nil)

  # Saving is also reading: you don't keep something you haven't opened.
  def save_item!
    update!(saved_at: Time.current, read_at: read_at || Time.current)
    feed.touch_read!(read_at)
  end

  def unsave! = update!(saved_at: nil)

  # The plain-text blurb the river shows. Feeds ship HTML of wildly varying
  # quality; the reader shows text, and the full article lives one click
  # away at the source (which is also why nothing here is rendered as HTML).
  def blurb(length = 320)
    summary.to_s.squish.truncate(length)
  end
end
