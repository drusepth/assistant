module Feeds
  # The reader's query object (D-feed-reader): one place that turns the
  # river's filters — hobby, feed, unread/saved — into a page of items, so
  # the controller stays a controller and the Hobbies panel can ask for the
  # same thing with different numbers.
  #
  # The order is chronological, full stop. Newest first, in the order the
  # world published it, the same for everybody looking at the same feeds.
  # That is a product decision rather than a missing feature: the sources
  # are ones the user picked one at a time, so there is nothing to sift —
  # and an ordering nobody can predict is exactly what the feeds this is an
  # alternative to are made of.
  class River
    PER_PAGE = 25
    FILTERS = %w[ unread saved all ].freeze

    Page = Data.define(:items, :next_offset, :total) do
      def more? = next_offset.present?
      def any? = items.any?
    end

    attr_reader :user, :filter, :section, :feed

    def initialize(user, filter: "unread", section: nil, feed: nil)
      @user = user
      @filter = FILTERS.include?(filter.to_s) ? filter.to_s : "unread"
      @section = section
      @feed = feed
    end

    # Counted and paged in SQL — there is no ranking pass to hold a window
    # in memory for.
    def page(offset: 0, per_page: PER_PAGE)
      items = scope.offset(offset).limit(per_page + 1).to_a
      more = items.length > per_page
      Page.new(items: items.first(per_page), next_offset: (offset + per_page if more), total: scope.count)
    end

    def unread_count = base.unread.count

    # Every item the filters admit, newest first.
    def scope
      items = base
      items = items.unread if filter == "unread"
      items = items.saved if filter == "saved"
      items.newest.includes(feed: :sections)
    end

    private
      # The one authorization line in the reader: a river is your own
      # subscriptions.
      def base = FeedItem.where(feed: feeds)

      def feeds
        scope = user.feeds.active
        scope = scope.where(id: feed) if feed
        scope = scope.in_section(section) if section
        scope
      end
  end
end
