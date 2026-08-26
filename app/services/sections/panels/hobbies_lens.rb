module Sections
  module Panels
    # One hobby's page (D-hobby-feeds). Reached through Panel's parent-lens
    # fallback rather than by name, because a lens is a row the user made and
    # no class can be named after its slug.
    #
    # This is the "filter to one hobby" half of the hub: the same river, the
    # same density, narrowed to the feeds filed under this lens — with the
    # everything-view one link away. Deeper than the hub card (a screenful,
    # not a taste) and shallower than /reader (no filter rows, no paging):
    # the page's other zones are what you came for, and the river is the part
    # that changed since yesterday.
    class HobbiesLens < Panel
      PREVIEW = 12

      def row = @row ||= ::Hobbies::Rivers.for(viewer, [ section ], preview: PREVIEW).sole

      def feeds = row.feeds
      def items = row.items
      def unread_count = row.unread_count

      # What counts as this hobby, as words (D-story-matching): the rule
      # that carries a broad feed's stories in here without the feed
      # itself moving. Unsaved until the first word — a hobby nobody has
      # written a rule for shouldn't cost a row.
      def watchlist = @watchlist ||= ::Watchlist.for(viewer, section)

      # The catch-all has no rule: it is where a story lands when nothing
      # claims it, so routing *into* it would mean nothing.
      def watchlist? = !::Hobbies::OtherInterests.catch_all?(section)

      def matched_this_week
        return 0 unless watchlist.persisted?

        @matched_this_week ||= watchlist.matches.live.since(1.week.ago).count
      end

      # The feeds this rule flooded, paired with the words that did it.
      def suspensions
        return [] unless watchlist.persisted? && watchlist.suspended_feed_ids.any?

        @suspensions ||= watchlist.suspended_feeds.map do |feed|
          row = watchlist.dropped.find { |entry| entry["feed_id"] == feed.id }
          Suspension.new(feed: feed, terms: row&.dig("term"))
        end
      end

      def model? = viewer.household.model_profile&.configured?

      # Words asked for and refused, with why — a dropped word is explained
      # rather than missing.
      def refused = watchlist.dropped.reject { |row| row["kind"] == "flood" }

      Suspension = Struct.new(:feed, :terms, keyword_init: true)
    end
  end
end
