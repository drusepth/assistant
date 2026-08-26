module Feeds
  module Watchlists
    # The guard that keeps one bad word from drowning a hobby
    # (D-story-matching §6).
    #
    # The corpus test (`Corpus`) catches a broad word before a rule saves,
    # but it can only see the river as it was. Feeds change: a site starts a
    # daily column, an aggregator gets loud, and a word that matched 5% of
    # last month's stories starts matching half of this week's. So the same
    # question is asked again at ingest, per feed, and the answer is
    # narrow — **this rule is paused for this feed**, not for the twelve
    # others where the same words file correctly.
    #
    # Suspension takes the unread matches from that feed with it. They are
    # the flood itself, nobody has looked at them, and every one of them is
    # re-derivable: Resume re-runs the backfill and they come back. Read
    # matches stay, because the user already spent attention on those and
    # the app doesn't get to take that back.
    class Flood
      WINDOW = 7.days
      # Under this, there is no flood — there is a feed that publishes a lot
      # about your hobby, which is the feature working.
      MIN_MATCHES = 10
      SHARE = 0.4

      def self.check(feed, watchlist, matches) = new(feed, watchlist, matches).check

      def initialize(feed, watchlist, matches)
        @feed = feed
        @watchlist = watchlist
        @matches = matches
      end

      def check
        return false if @watchlist.resumed_for?(@feed)
        return false if matched < MIN_MATCHES || total.zero?
        return false if matched.fdiv(total) < SHARE

        @watchlist.suspend!(@feed, reason: culprits)
        drain
        true
      end

      private
        def recent = @feed.feed_items.where(created_at: WINDOW.ago..)

        def total = @total ||= recent.count

        def matched
          @matched ||= FeedItemMatch.live
            .where(section_id: @watchlist.section_id, feed_item_id: recent.select(:id)).count
        end

        # The words doing it, so the notice can name them rather than
        # telling the user their list is bad somewhere.
        def culprits
          @matches.flat_map(&:terms).tally.max_by(2) { |_term, count| count }.map(&:first).join(", ")
        end

        def drain
          FeedItemMatch.live.where(section_id: @watchlist.section_id,
                                   feed_item_id: @feed.feed_items.unread.select(:id)).delete_all
        end
    end
  end
end
