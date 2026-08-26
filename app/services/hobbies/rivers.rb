module Hobbies
  # One river per hobby (D-hobby-feeds), batched for the hub grid.
  #
  # The hub asks the same three questions about every lens — how many feeds,
  # how many unread, what are the newest few — and asking them lens by lens
  # would be three queries per card. Feeds and their taggings load once here
  # and are grouped in Ruby; only the newest-items query runs per lens, and
  # only for lenses that actually have a feed. A household with a dozen
  # hobbies and no feeds costs two queries.
  class Rivers
    PREVIEW = 3

    Row = Struct.new(:section, :feeds, :unread_count, :items, keyword_init: true) do
      def any_feeds? = feeds.any?
      # A hobby can be fed entirely by matched stories (D-story-matching):
      # no feed of its own, and a river all the same.
      def any_river? = feeds.any? || items.any? || unread_count.positive?
      def catch_all? = Hobbies::OtherInterests.catch_all?(section)
    end

    def self.for(viewer, sections, preview: PREVIEW)
      new(viewer, sections, preview: preview).rows
    end

    def initialize(viewer, sections, preview: PREVIEW)
      @viewer = viewer
      @sections = Array(sections)
      @preview = preview
    end

    def rows
      @sections.map do |section|
        feeds = feeds_by_section.fetch(section.id, [])
        matched = matched_unread.fetch(section.id, [])
        Row.new(
          section: section, feeds: feeds,
          unread_count: feeds.sum { |feed| unread_counts.fetch(feed.id, 0) } + matched.size,
          items: newest_unread(feeds, matched)
        )
      end
    end

    private
      attr_reader :viewer, :preview

      def feeds = @feeds ||= viewer.feeds.active.includes(:sections).to_a

      # A feed can carry several lenses — that is the point of the lens
      # model — so this is a fan-out, not a group_by.
      def feeds_by_section
        @feeds_by_section ||= feeds.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |feed, map|
          feed.sections.each { |section| map[section.id] << feed }
        end
      end

      def unread_counts
        @unread_counts ||= FeedItem.where(feed: feeds).unread.group(:feed_id).count
      end

      # A hobby's card carries the stories matched to it as well as the ones
      # its own feeds published (D-story-matching): that is the whole point
      # of matching — a hobby whose feeds are quiet but whose subject is in
      # the news now has something to show.
      def newest_unread(feeds, matched)
        return [] if (feeds.empty? && matched.empty?) || preview.zero?

        scope = FeedItem.unread.where(feed_id: feeds.map(&:id))
        scope = scope.or(FeedItem.unread.where(id: matched)) if matched.any?
        scope.newest.includes(:feed, matches: :section).limit(preview).to_a
      end

      # One query for every lens on the page, and it counts only what the
      # feed half doesn't already: a story whose feed later gained this
      # hobby is in the river once, not twice.
      def matched_unread
        @matched_unread ||= FeedItemMatch.live.joins(:feed_item)
          .where(section_id: @sections.map(&:id))
          .where(feed_items: { read_at: nil, feed_id: feeds.map(&:id) })
          .pluck(:section_id, :feed_item_id, "feed_items.feed_id")
          .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(section_id, item_id, feed_id), map|
            next if feeds_by_section.fetch(section_id, []).any? { |feed| feed.id == feed_id }

            map[section_id] << item_id
          end
      end
  end
end
