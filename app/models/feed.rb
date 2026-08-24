# A source the reader follows for one user (D-feed-reader): an RSS, Atom or
# JSON feed the user chose, tagged with the hobby lenses it belongs to. The
# subscription is a primitive like any other — Visible so a section grant
# can expose what you follow, Sectionable so "Guitar" is a filter over the
# river rather than a folder of its own.
#
# Subscriptions are per-user on purpose: two household members who follow
# the same site each get their own row, because read/saved/vote state is
# personal and sharing a row would mean sharing whether you'd read
# something (Q-feed-sharing).
class Feed < ApplicationRecord
  include Visible
  include Sectionable

  KINDS = %w[ rss atom json ].freeze

  # How stale a feed has to be before the scheduled refresh picks it up.
  # Hourly is the polite floor for a household polling somebody else's
  # server; a feed nobody has opened in a month backs off further.
  REFRESH_EVERY = 1.hour
  DORMANT_AFTER = 30.days
  DORMANT_REFRESH_EVERY = 12.hours
  # A feed that keeps failing is checked less often rather than hammered;
  # the row says why, and a manual refresh always overrides the backoff.
  MAX_BACKOFF = 24.hours

  # What one feed keeps. Old *read* items are pruned to this on refresh —
  # a reader is a river, not an archive — and saved items are never pruned.
  KEEP_PER_FEED = 250

  has_many :feed_items, -> { order(published_at: :desc, id: :desc) }, dependent: :destroy,
    inverse_of: :feed

  validates :url, presence: true,
    format: { with: %r{\Ahttps?://\S+\z}i, message: "must be an http(s) link" },
    uniqueness: { scope: :user_id, message: "is already in your reader" }
  validates :kind, inclusion: { in: KINDS }
  validates :title, :label, length: { maximum: 200 }

  normalizes :label, :title, with: ->(value) { value.to_s.squish.presence }

  scope :active, -> { where(active: true) }
  scope :failing, -> { where.not(last_error: nil) }

  # The cheap SQL prefilter for the scheduled sweep: nothing fetched inside
  # the base interval can be due. `due_for_refresh?` then decides exactly,
  # since backoff and dormancy need the feed's own history.
  scope :due_for_refresh, ->(now = Time.current) {
    active.where(last_fetched_at: [ nil, ..(now - REFRESH_EVERY) ])
  }

  def display_title = label.presence || title.presence || host || url

  def host
    URI.parse(url.to_s).host&.delete_prefix("www.")
  rescue URI::InvalidURIError
    nil
  end

  def unread_count = feed_items.unread.count

  def healthy? = last_error.blank?

  # The interval this feed has earned: the polite hourly default, backed off
  # after repeated failures, and stretched once nothing here has been read
  # in a month (the reader is not a crawler — an abandoned feed should cost
  # its publisher almost nothing).
  def refresh_interval
    interval = REFRESH_EVERY
    interval = [ interval * (2**failure_count), MAX_BACKOFF ].min if failure_count.positive?
    interval = [ interval, DORMANT_REFRESH_EVERY ].max if dormant?
    interval
  end

  def due_for_refresh?(now = Time.current)
    active? && (last_fetched_at.nil? || last_fetched_at <= now - refresh_interval)
  end

  def dormant?
    return false if last_item_at.nil?

    feed_items.where(read_at: DORMANT_AFTER.ago..).none? && last_item_at < DORMANT_AFTER.ago
  end

  def record_success!(last_item_at: nil)
    update!(
      last_fetched_at: Time.current, last_error: nil, failure_count: 0,
      last_item_at: [ last_item_at, self.last_item_at ].compact.max
    )
  end

  def record_failure!(message)
    update!(
      last_fetched_at: Time.current, failure_count: failure_count + 1,
      last_error: message.to_s.truncate(200)
    )
  end
end
