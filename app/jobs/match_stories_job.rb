# Re-reads a hobby's watchlist over the stories already in the box
# (D-story-matching §3.2): what a rule change means for everything that
# arrived before it.
#
# Bounded on purpose. A reader is a river, not an archive, so the backfill
# looks at the window a reader would look at — the newest few hundred items
# of the feeds that don't already carry this hobby — rather than at
# everything SQLite happens to still hold.
#
# It clears this rule's own live matches first, because a term the user
# just deleted should take its rows with it. Two kinds of row survive that
# clearing: a **rejected** one (the tombstone is the memory that stops it
# coming back) and a **hand-filed** one (a rule never overwrites a human).
class MatchStoriesJob < ApplicationJob
  queue_as :default

  WINDOW = 30.days
  LIMIT = 500

  def perform(watchlist)
    clear(watchlist)
    return unless watchlist.any_terms?

    matcher = Feeds::Match.new(watchlist.user, watchlists: [ watchlist ])
    feeds(watchlist).each { |feed| matcher.call(feed, items_for(feed)) }
  end

  private
    def clear(watchlist)
      watchlist.matches.live.source_match.delete_all
    end

    # Every active feed the user follows that doesn't already carry this
    # hobby — a feed that does needs no exception for it.
    def feeds(watchlist)
      watchlist.user.feeds.active.includes(:sections).reject do |feed|
        feed.section_ids.include?(watchlist.section_id) || watchlist.suspended_for?(feed)
      end
    end

    def items_for(feed)
      feed.feed_items.recent(WINDOW).newest.limit(LIMIT).to_a
    end
end
