# What a hobby means to you, as words (D-story-matching).
#
# D-hobby-feeds files *feeds*, which is right for the eight that are each
# about one thing and wrong for the two that aren't: a general news feed's
# birding stories are unreachable from Birding, and filing that feed under
# Birding would flood it with the other 95%. A watchlist is the way out that
# costs no model call per story — terms that mean this hobby, negatives that
# don't, matched offline at ingest by `Feeds::Match`.
#
# **Per user, not per section.** A lens is household-shared; this is not. It
# is learned from private reading and private corrections, and a shared rule
# would leak one member's rejections into another's river (D9).
#
# The rule is one sentence on purpose, because it has to be explainable on
# the page where it is edited: *a term in the title, or two distinct terms
# anywhere, and no negative*. Terms are strings, never patterns — validated
# on the way in by `Feeds::Watchlists::Terms`, so nothing a model or a
# stranger's XML writes can become a regex, a query, or anything but a word.
class Watchlist < ApplicationRecord
  belongs_to :user
  belongs_to :section

  # Enough words to describe a hobby, few enough to read at a glance and
  # fix by hand. A list nobody can audit is the failure mode this whole
  # design exists to avoid.
  MAX_TERMS = 24
  MAX_NEGATIVES = 16

  enum :source, { hand: "hand", model: "model" }, default: :hand, prefix: true

  validates :user_id, uniqueness: { scope: :section_id }

  scope :with_terms, -> { where.not(terms: []) }

  def self.for(user, section)
    find_or_initialize_by(user: user, section: section)
  end

  def any_terms? = terms.present?

  # The matches this rule is responsible for — a subquery rather than a
  # join, because clearing them is a `delete_all` and Rails won't delete
  # through a join.
  def matches
    FeedItemMatch.where(section_id: section_id,
                        feed_item_id: FeedItem.where(feed_id: user.feeds.select(:id)).select(:id))
  end

  def add(term, kind: :terms)
    words = Feeds::Watchlists::Terms.clean([ term ])
    return false if words.empty?

    list = (public_send(kind) + words).uniq.first(kind.to_sym == :negatives ? MAX_NEGATIVES : MAX_TERMS)
    update!(kind => list, dropped: dropped.reject { |row| words.include?(row["term"]) }, **reopened)
  end

  def remove(term, kind: :terms)
    update!(kind => public_send(kind) - [ term.to_s.downcase ], **reopened)
  end

  # A feed this rule flooded, and the way back. Suspension is per feed
  # rather than per rule: one broad feed drowning in "birds" says nothing
  # about the twelve narrow ones the same words file correctly.
  def suspended_for?(feed) = suspended_feed_ids.include?(feed.id)

  # Both of these edit a list, and the guard runs in a job while a page may
  # be holding a copy of this row: reload first, or a stale `[]` silently
  # writes away a suspension somebody else just recorded. (`update!` only
  # writes changed attributes, so the stale write doesn't even show up as
  # one — it just doesn't happen.)
  def suspend!(feed, reason:)
    reload
    update!(suspended_feed_ids: (suspended_feed_ids + [ feed.id ]).uniq,
            dropped: dropped + [ { "term" => reason, "feed_id" => feed.id, "kind" => "flood" } ])
  end

  # A resume is a decision, and the guard does not overrule a decision: the
  # feed is remembered as one the user has already been warned about, so
  # "Watch it again" doesn't just start a fight the app wins every night.
  # Changing the words is a new question, and `reopened` asks it again.
  def resume!(feed)
    reload
    update!(suspended_feed_ids: suspended_feed_ids - [ feed.id ],
            resumed_feed_ids: (resumed_feed_ids + [ feed.id ]).uniq,
            dropped: dropped.reject { |row| row["feed_id"] == feed.id })
  end

  def resumed_for?(feed) = resumed_feed_ids.include?(feed.id)

  def suspended_feeds = user.feeds.where(id: suspended_feed_ids)

  private
    def reopened = resumed_feed_ids.any? ? { resumed_feed_ids: [] } : {}
end
