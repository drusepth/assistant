# Where a place's happenings come from (D-listing-feeds): an iCalendar feed,
# a page carrying schema.org Event data, or — opt-in, later — a keyed
# provider queried by the place's point. One seam above the kind: a source
# yields parsed items and the ingest is the same.
#
# This is the second part of the app that polls strangers' servers on a
# timer, and it inherits the reader's politeness whole (Feed): conditional
# GET with the publisher's validators echoed raw, backoff capped at a day,
# every fetch through Web::Fetch, only *adding* fetches in the request. Two
# numbers differ because listings are not news — a 6-hour floor rather than
# an hour, and a place nobody opens drops to daily.
class ListingSource < ApplicationRecord
  belongs_to :place, inverse_of: :listing_sources
  has_one :user, through: :place
  has_many :happenings, dependent: :destroy, inverse_of: :listing_source

  # `account` is fed by a linked account's sync (D-radar-accounts) rather
  # than fetched: the rows the user saved on Meetup, filed under the place
  # they are nearest.
  KINDS = %w[ ics page provider account ].freeze
  FETCHED_KINDS = %w[ ics page provider ].freeze

  # The opt-in searches (D-listing-feeds §8): keyed APIs queried by a
  # place's point and radius. One entry per provider, the D26 registry
  # shape — its fields, and the sentence its switch has to say out loud.
  PROVIDERS = {
    "ticketmaster" => {
      label: "Ticketmaster",
      service: "Listings::Providers::Ticketmaster",
      url: "https://app.ticketmaster.com/discovery/v2/events.json",
      blurb: "Concerts, sports and theatre with tickets on sale — the paid-ticket world no city calendar lists.",
      consent: "This sends the place's coordinates and radius to Ticketmaster on every check.",
      fields: [
        { key: "api_key", label: "Ticketmaster API key", secret: true,
          hint: "Free from developer.ticketmaster.com — the Consumer Key of an app you create there." }
      ]
    }
  }.freeze

  REFRESH_EVERY = 6.hours
  DORMANT_AFTER = 30.days
  DORMANT_REFRESH_EVERY = 24.hours
  MAX_BACKOFF = 24.hours

  # Per-source settings and, for a provider, its key — encrypted like a
  # linked account's credentials, and never shown back.
  serialize :credentials, coder: JSON
  encrypts :credentials

  validates :url, presence: true,
    format: { with: %r{\Ahttps?://\S+\z}i, message: "must be an http(s) link" },
    uniqueness: { scope: :place_id, message: "is already followed for this place" }
  validates :kind, inclusion: { in: KINDS }
  validates :provider, inclusion: { in: PROVIDERS.keys }, if: :provider?
  validates :title, length: { maximum: 200 }

  normalizes :title, with: ->(value) { value.to_s.squish.presence }

  scope :active, -> { where(active: true) }
  scope :failing, -> { where.not(last_error: nil) }
  scope :fetchable, -> { where(kind: FETCHED_KINDS) }
  scope :due_for_refresh, ->(now = Time.current) {
    active.fetchable.where(last_fetched_at: [ nil, ..(now - REFRESH_EVERY) ])
  }

  def display_title = title.presence || host || url

  def host
    URI.parse(url.to_s).host&.delete_prefix("www.")
  rescue URI::InvalidURIError
    nil
  end

  def healthy? = last_error.blank?

  def provider? = kind == "provider"
  def fetched? = FETCHED_KINDS.include?(kind)
  def provider_settings = PROVIDERS.fetch(provider.to_s, {})
  def provider_service = provider_settings[:service]&.constantize

  def refresh_interval(now = Time.current)
    interval = REFRESH_EVERY
    interval = [ interval * (2**failure_count), MAX_BACKOFF ].min if failure_count.positive?
    interval = [ interval, DORMANT_REFRESH_EVERY ].max if dormant?(now)
    interval
  end

  def due_for_refresh?(now = Time.current)
    active? && fetched? && (last_fetched_at.nil? || last_fetched_at <= now - refresh_interval(now))
  end

  # Nothing new in a month and nobody has opened this place in a month.
  def dormant?(now = Time.current)
    return false if last_item_at.nil? || last_item_at >= now - DORMANT_AFTER

    opened = place.last_opened_at
    opened.nil? || opened < now - DORMANT_AFTER
  end

  def record_success!(new_items: 0, etag: nil, last_modified: nil)
    update!(
      last_fetched_at: Time.current, last_error: nil, failure_count: 0,
      last_item_at: new_items.positive? ? Time.current : last_item_at,
      etag: etag, last_modified: last_modified
    )
  end

  def record_failure!(message)
    update!(
      last_fetched_at: Time.current, failure_count: failure_count + 1,
      last_error: message.to_s.truncate(200)
    )
  end

  # The publisher's own words from last time, echoed exactly.
  def conditional_headers
    { "If-None-Match" => etag, "If-Modified-Since" => last_modified }.compact_blank
  end
end
