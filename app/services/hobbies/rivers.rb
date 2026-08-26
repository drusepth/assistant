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
        Row.new(
          section: section, feeds: feeds,
          unread_count: feeds.sum { |feed| unread_counts.fetch(feed.id, 0) },
          items: newest_unread(feeds)
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

      def newest_unread(feeds)
        return [] if feeds.empty? || preview.zero?

        FeedItem.where(feed: feeds).unread.newest.includes(:feed).limit(preview).to_a
      end
  end
end
