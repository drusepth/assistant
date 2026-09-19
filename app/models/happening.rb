# One thing a listing source published (D-listing-feeds): a candidate, not
# an Event. The calendar is the user's own life and nothing lands on it
# without a click, so happenings have their own table and their own verbs,
# and an Event is created from one only by "Add to calendar" or an accepted
# suggestion — at which point `event_id` links them, so the row can say "on
# your calendar" and the watcher can tell handled from ignored.
#
# Two kinds: a dated `event`, and an undated `opening` — a volunteer role
# that is looking for people, open until its source stops listing it. Two
# provenances: `listed` from a stranger's calendar (the model's to judge),
# and `saved` from the user's own account (already judged, never read by
# the model — D-radar-accounts).
#
# Idempotent by `uid` within its source, like a feed item by guid. A
# recurring rule yields one row per occurrence sharing the master's
# `series_uid`, which is what lets a weekly meetup be judged once.
class Happening < ApplicationRecord
  belongs_to :listing_source, inverse_of: :happenings
  has_one :place, through: :listing_source
  has_one :user, through: :place
  belongs_to :event, optional: true
  belongs_to :task, optional: true

  # The model's judgments about this row (D-event-radar). `matches` is the
  # live set — what a row wears and what the watcher reads; a rejected one
  # is a tombstone that stays as an example.
  has_many :happening_matches, dependent: :destroy
  has_many :matches, -> { live }, class_name: "HappeningMatch", inverse_of: :happening, dependent: nil
  has_many :matched_sections, through: :matches, source: :section

  enum :kind, { event: "event", opening: "opening" }, default: :event, prefix: true
  enum :provenance, { listed: "listed", saved: "saved" }, default: :listed, prefix: true

  # Past a month, gone: the radar is not an archive, and the calendar keeps
  # what you kept.
  PRUNE_AFTER = 30.days
  # How far ahead the river shows. The watcher's lead time is the place's.
  HORIZON = 120.days

  validates :uid, :title, presence: true
  validates :starts_at, presence: true, if: :kind_event?
  validates :title, length: { maximum: 300 }
  validates :location, :url, length: { maximum: 2_000 }

  scope :visible, -> { where(hidden_at: nil) }
  scope :hidden, -> { where.not(hidden_at: nil) }
  scope :in_range, -> { where(out_of_range: false) }
  scope :live, -> { where(withdrawn_at: nil) }
  scope :withdrawn, -> { where.not(withdrawn_at: nil) }
  scope :unmatched, -> { where(matched_at: nil) }
  scope :unlinked, -> { where(event_id: nil, task_id: nil) }
  # Judged for this person — by the model, or by the person themselves
  # (a saved row carries its own judgment and never needed one).
  scope :matched, -> {
    where(id: HappeningMatch.live.select(:happening_id)).or(where(provenance: "saved"))
  }
  # Still to come: a dated row whose end hasn't passed, or an opening still
  # listed and not past its own closing date.
  scope :upcoming, ->(now = Time.current) {
    where(kind: "event").where("COALESCE(happenings.ends_at, happenings.starts_at) >= ?", now)
      .or(where(kind: "opening", withdrawn_at: nil).where("happenings.expires_on IS NULL OR happenings.expires_on >= ?", now.to_date))
  }
  scope :starting_within, ->(range) { where(starts_at: range.begin.beginning_of_day..range.end.end_of_day) }
  scope :by_start, -> { order(Arel.sql("happenings.starts_at IS NULL, happenings.starts_at ASC"), id: :asc) }
  scope :for_user, ->(user) { where(listing_source_id: ListingSource.where(place_id: user.places.select(:id)).select(:id)) }

  def hidden? = hidden_at.present?
  def withdrawn? = withdrawn_at.present?
  def on_calendar? = event_id.present?
  def on_board? = task_id.present?
  def linked? = on_calendar? || on_board?
  def located? = latitude.present? && longitude.present?

  def hide! = update!(hidden_at: Time.current)
  def unhide! = update!(hidden_at: nil)

  def matched? = provenance_saved? || matches.any?

  # The one chip a row wears: the first live match.
  def match = matches.first

  def source_name = listing_source.display_title

  # The day this belongs under. An opening has no date; it sorts by when it
  # was first seen, which is what "new" means for a role.
  def on = (starts_at || created_at).to_date

  def expired?(today = Date.current) = expires_on.present? && expires_on < today

  # "Add to calendar": the one path from a happening to an Event, shared by
  # the river's verb and an accepted suggestion (D-event-radar) so the event
  # is identical whichever way it arrived. Idempotent — a second click
  # returns the event already made.
  def add_to_calendar!(sections: calendar_sections)
    return event if on_calendar?

    created = user.events.create!(
      title: title, starts_at: starts_at, ends_at: ends_at, all_day: all_day,
      location: location, description: calendar_description
    )
    created.sections = sections
    update!(event: created)
    created
  end

  # "Make a task": an opening's verb, and an event's "look into this" —
  # the board is where "I should" becomes "I did".
  def make_task!(sections: calendar_sections)
    return task if on_board?

    created = user.tasks.create!(title: task_title, notes: calendar_description, bucket: :later)
    created.sections = sections
    update!(task: created)
    created
  end

  # What the event or task is filed under: the section the radar lives in,
  # plus the lens it matched — a bird walk that matched Birding lands
  # tagged Hobbies and Birding, which is the multi-tagging the lens model
  # exists for. A cause files under People, communities being what the
  # section is.
  def calendar_sections
    slugs = kind_opening? ? %w[ people ] : %w[ hobbies ]
    slugs << "people" if matches.any?(&:causes?)
    slugs << "education" if matches.any?(&:subject?)
    # Inside one of the user's trip windows, it is also a Travel item —
    # the thing you'll do in Lisbon belongs to the trip (D-place-subscriptions).
    slugs << "travel" if Radar::Windows.new(user).cover?(self)
    (Section.where(slug: slugs).to_a + matched_sections.to_a).uniq
  end

  private
    def task_title
      kind_opening? ? "Look into volunteering: #{title}" : "Look into: #{title}"
    end

    def calendar_description
      lines = [ description.presence ]
      lines << "Source: #{source_name}"
      lines << "Link: #{url}" if url.present?
      lines.compact.join("\n\n")
    end
end
