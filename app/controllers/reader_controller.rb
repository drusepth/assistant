# The river (D-feed-reader): everything the user's feeds carried, newest
# first, filtered to unread, saved, or everything, and narrowed to one hobby
# lens or one feed.
#
# Google Reader's shape, and deliberately not more than that: the sources
# were each chosen by hand, so the reader's job is to show what arrived, in
# the order it arrived, and get out of the way.
class ReaderController < ApplicationController
  def index
    @river = Feeds::River.new(
      Current.user, filter: params[:filter] || "unread", section: hobby_lens, feed: own_feed_id
    )
    @page = @river.page(offset: params[:offset].to_i.clamp(0, 10_000))
    @feeds = Current.user.feeds.includes(:sections).order(:created_at)
    @unread_counts = FeedItem.where(feed: @feeds).unread.group(:feed_id).count
    # A hobby's pile is its feeds' unread *plus* the stories routed into it
    # (D-story-matching) — so a hobby whose own feeds are quiet still has a
    # count, and a hobby with no feeds at all still has a row.
    @routed_counts = routed_counts
    @lenses = lenses
    # The rail and the phone's scope sheet render the same tree, so it is
    # grouped once here: feeds under the hobby they were filed under
    # (D-hobby-feeds), catch-all last because it is where things land rather
    # than a hobby that happens to sort under O.
    @feeds_by_lens = @lenses
      .sort_by { |lens| [ Hobbies::OtherInterests.catch_all?(lens) ? 1 : 0, lens.name ] }
      .index_with { |lens| @feeds.select { |feed| feed.section_ids.include?(lens.id) } }
    @scope_lens = hobby_lens
    @scope_feed = @feeds.find { |feed| feed.id == own_feed_id }
    # Only while there is nothing to read: a shelf above a river is clutter
    # (D-hobby-feeds §7.1).
    @starters = Feeds::Starters.groups if @feeds.none?
  end

  # "Mark everything I'm looking at as read" — the verb that keeps a river
  # from becoming a guilt pile. Scoped to the current filters, never to
  # every feed the user has.
  def read_all
    river = Feeds::River.new(Current.user, filter: "unread", section: hobby_lens, feed: own_feed_id)
    # By id rather than on the scope: the river's scope carries a LIMIT, and
    # SQLite is usually built without UPDATE … LIMIT.
    ids = river.scope.unread.pluck(:id)
    feed_ids = FeedItem.where(id: ids).distinct.pluck(:feed_id)
    count = FeedItem.where(id: ids).update_all(read_at: Time.current, updated_at: Time.current)
    # `update_all` skips the callback that would have stamped each feed, and
    # that stamp is what keeps a feed nobody reads from being polled as if
    # somebody did — so do it here, in one statement.
    Feed.where(id: feed_ids).update_all(last_read_at: Time.current) if feed_ids.any?
    redirect_to return_to_path(request.referer.presence || reader_path),
      notice: count.positive? ? "#{helpers.pluralize(count, "item")} marked read." : "Nothing left to mark read."
  end

  # Read-on-scroll (D-reader-density). A four-hundred item backlog used to
  # have exactly two outcomes — four hundred clicks, or Mark all read — and
  # anybody sane picked the second and threw the pile away unseen. So items
  # scrolled fully past mark themselves read, and the ledger keeps one Undo.
  #
  # Batched rather than one request per row: a thumb flicking through thirty
  # headlines would otherwise open thirty connections and stamp each feed
  # thirty times.
  def read_seen = seen { |scope| scope.update_all(read_at: Time.current, updated_at: Time.current) }

  def unread_seen = seen { |scope| scope.update_all(read_at: nil, updated_at: Time.current) }

  private
    # The one authorization line for the batch: ids are narrowed to the
    # caller's own feeds before anything is written, so a forged id in the
    # list updates nothing and the request still succeeds for the rest.
    def seen
      ids = Array(params[:ids]).first(200).map(&:to_i)
      scope = FeedItem.where(feed: Current.user.feeds, id: ids)
      feed_ids = scope.distinct.pluck(:feed_id)
      count = yield(scope)
      # `update_all` skips the callback that would have stamped each feed,
      # and that stamp is what keeps a feed nobody reads from being polled
      # as if somebody did.
      Feed.where(id: feed_ids).update_all(last_read_at: Time.current) if feed_ids.any?
      render json: { count: count }
    end

    # Every hobby with a feed filed under it, plus every hobby something has
    # been routed into.
    def lenses
      hobbies = Section.find_by(slug: "hobbies")
      return [] unless hobbies

      hobbies.children.where(id: @feeds.flat_map(&:section_ids) | @routed_counts.keys).order(:name)
    end

    def routed_counts
      StoryRouting.live.joins(:feed_item)
        .where(feed_items: { read_at: nil, feed_id: @feeds.map(&:id) })
        .group(:section_id).distinct.count(:feed_item_id)
    end

    def hobby_lens
      return nil if params[:hobby].blank?

      Section.find_by(slug: params[:hobby])
    end

    # A feed id from params is only ever one of this user's own — the river
    # reads FeedItem directly, so the ownership check happens here.
    def own_feed_id
      return nil if params[:feed].blank?

      Current.user.feeds.where(id: params[:feed]).pick(:id)
    end
end
