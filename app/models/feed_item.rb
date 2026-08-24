# One entry from a followed feed (D-feed-reader). It is not a primitive and
# not Sectionable: an item's tags are its feed's tags, so filing happens
# once, at the subscription, and the river's hobby filter is a join rather
# than a per-item write. Items are disposable — the ones worth keeping
# become Tasks, Notes, or saves.
class FeedItem < ApplicationRecord
  belongs_to :feed
  has_one :user, through: :feed

  UP = 1
  DOWN = -1

  validates :guid, :title, presence: true
  validates :vote, inclusion: { in: [ DOWN, 0, UP ] }

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :saved, -> { where.not(saved_at: nil) }
  scope :newest, -> { order(Arel.sql("COALESCE(published_at, feed_items.created_at) DESC"), id: :desc) }
  # The window the river ranks over, and what a refresh may prune down to.
  scope :recent, ->(within = 30.days) {
    where("COALESCE(published_at, feed_items.created_at) >= ?", within.ago)
  }

  def read? = read_at.present?
  def saved? = saved_at.present?
  def upvoted? = vote == UP
  def downvoted? = vote == DOWN

  def published_on = (published_at || created_at)

  def source_name = feed.display_title

  def mark_read! = update!(read_at: Time.current)
  def mark_unread! = update!(read_at: nil)

  # Saving is also reading: you don't keep something you haven't opened.
  def save_item!
    update!(saved_at: Time.current, read_at: read_at || Time.current)
  end

  def unsave! = update!(saved_at: nil)

  # A vote is a toggle — pressing the same arrow again clears it, the way
  # every voting UI people already use behaves.
  def vote!(direction)
    direction = direction.to_i.clamp(DOWN, UP)
    update!(vote: vote == direction ? 0 : direction)
  end

  # The plain-text blurb the river shows. Feeds ship HTML of wildly varying
  # quality; the reader shows text, and the full article lives one click
  # away at the source (which is also why nothing here is rendered as HTML).
  def blurb(length = 320)
    summary.to_s.squish.truncate(length)
  end

  # Everything the ranking's keyword match reads: the words the publisher
  # chose, not the words we guessed.
  def text_for_matching = [ title, author, summary ].compact.join(" ")
end
