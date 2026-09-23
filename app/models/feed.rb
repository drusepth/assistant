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
  # Filing a feed under its hobbies is the reader's one model call
  # (D-hobby-feeds), and it is the same quick-add-then-sort shape the other
  # primitives use: the user pastes a URL, the model does the paperwork.
  include AutoSortable

  AUTO_SORT_JOB = ClassifyFeedJob

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

  # The sweep's prefilter: nothing fetched inside the base interval can be
  # due. `due_for_refresh?` then decides exactly — the exponential backoff
  # is arithmetic SQLite has no portable function for, and it now costs
  # nothing to apply in Ruby, because dormancy is a column read rather
  # than the per-feed query it used to be (`last_read_at`).
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

  # A model has looked at this feed, whatever it concluded — which is not
  # the same as the feed having a hobby, since "none of them" is a valid
  # and common answer.
  def classified? = classified_at.present?

  # The interval this feed has earned: the polite hourly default, backed off
  # after repeated failures, and stretched once nothing here has been read
  # in a month (the reader is not a crawler — an abandoned feed should cost
  # its publisher almost nothing).
  def refresh_interval(now = Time.current)
    interval = REFRESH_EVERY
    interval = [ interval * (2**failure_count), MAX_BACKOFF ].min if failure_count.positive?
    interval = [ interval, DORMANT_REFRESH_EVERY ].max if dormant?(now)
    interval
  end

  def due_for_refresh?(now = Time.current)
    active? && (last_fetched_at.nil? || last_fetched_at <= now - refresh_interval(now))
  end

  # Nothing new in a month and nothing read here in a month. Reads only
  # columns on this row — `last_read_at` is denormalized from the items on
  # purpose, so the sweep never asks the database once per feed.
  def dormant?(now = Time.current)
    return false if last_item_at.nil? || last_item_at >= now - DORMANT_AFTER

    last_read_at.nil? || last_read_at < now - DORMANT_AFTER
  end

  def record_success!(last_item_at: nil, etag: nil, last_modified: nil)
    update!(
      last_fetched_at: Time.current, last_error: nil, failure_count: 0,
      last_item_at: [ last_item_at, self.last_item_at ].compact.max,
      etag: etag, last_modified: last_modified
    )
  end

  # What we send back to ask "anything new?" — the publisher's own words
  # from last time, echoed exactly (D-feed-reader).
  def conditional_headers
    { "If-None-Match" => etag, "If-Modified-Since" => last_modified }.compact_blank
  end

  # Somebody read something here. Denormalized so the sweep can see it in
  # SQL; `update_column` because this is bookkeeping, not an edit.
  def touch_read!(at = Time.current)
    update_column(:last_read_at, at) if last_read_at.nil? || last_read_at < at
  end

  # Stamped the moment a check starts, then overwritten by however it ends.
  # A check that never ends — the worker killed mid-fetch, as an oversized
  # feed once did to it every fifteen minutes — would otherwise leave the
  # feed exactly as due as before, so the next sweep hands the same feed
  # to the next worker. Counted as a failure up front, a crash earns the
  # backoff any other failure does, and the reader has something to show.
  INTERRUPTED = "the last check didn't finish".freeze

  def record_attempt!
    record_failure!(INTERRUPTED)
  end

  # How a check that already stamped its attempt says why it failed: the
  # attempt counted the failure, so only the words change.
  def explain_failure!(message)
    update!(last_error: message.to_s.truncate(200))
  end

  def record_failure!(message)
    update!(
      last_fetched_at: Time.current, failure_count: failure_count + 1,
      last_error: message.to_s.truncate(200)
    )
  end
end
