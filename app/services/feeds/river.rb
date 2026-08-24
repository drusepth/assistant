module Feeds
  # The reader's query object (D-feed-reader): one place that turns the
  # river's filters — hobby, feed, unread/saved, interesting/newest — into
  # a page of items, so the controller stays a controller and the panel can
  # ask for the same thing with different numbers.
  #
  # "Interesting" ranks in Ruby over a bounded window rather than in SQL.
  # That is a deliberate ceiling, not an oversight: the ordering is a decay
  # curve over a stored score (Rank), a window of a few hundred rows is
  # everything a household reader has unread at once, and the alternative —
  # a materialised score column recomputed on a clock — would drift and
  # would still need this pass to be correct.
  class River
    WINDOW = 400
    PER_PAGE = 25
    FILTERS = %w[ unread saved all ].freeze
    SORTS = %w[ interesting new ].freeze

    Page = Data.define(:items, :next_offset, :total) do
      def more? = next_offset.present?
      def any? = items.any?
    end

    attr_reader :user, :filter, :sort, :section, :feed

    def initialize(user, filter: "unread", sort: "interesting", section: nil, feed: nil)
      @user = user
      @filter = FILTERS.include?(filter.to_s) ? filter.to_s : "unread"
      @sort = SORTS.include?(sort.to_s) ? sort.to_s : "interesting"
      @section = section
      @feed = feed
    end

    def page(offset: 0, per_page: PER_PAGE)
      ranked = ordered
      Page.new(
        items: ranked[offset, per_page] || [],
        next_offset: (offset + per_page if ranked.length > offset + per_page),
        total: ranked.length
      )
    end

    def unread_count = base.unread.count

    # Every item the filters admit, newest first, capped at the window.
    def scope
      items = base
      items = items.unread if filter == "unread"
      items = items.saved if filter == "saved"
      items.newest.limit(WINDOW).includes(feed: :sections)
    end

    private
      def ordered
        @ordered ||= sort == "new" ? scope.to_a : Rank.sort(scope.to_a)
      end

      # The one authorization line in the reader: a river is your own
      # subscriptions. Read state is personal, so a feed shared into the
      # household appears in the sharer's river only (Q-feed-sharing).
      def base = FeedItem.where(feed: feeds)

      def feeds
        scope = user.feeds.active
        scope = scope.where(id: feed) if feed
        scope = scope.in_section(section) if section
        scope
      end
  end
end
