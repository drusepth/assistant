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
    @lenses = Section.find_by(slug: "hobbies")&.children&.where(id: @feeds.flat_map(&:section_ids))&.order(:name) || []
    @unread_counts = FeedItem.where(feed: @feeds).unread.group(:feed_id).count
  end

  # "Mark everything I'm looking at as read" — the verb that keeps a river
  # from becoming a guilt pile. Scoped to the current filters, never to
  # every feed the user has.
  def read_all
    river = Feeds::River.new(Current.user, filter: "unread", section: hobby_lens, feed: own_feed_id)
    count = FeedItem.where(id: river.scope.unread.pluck(:id))
      .update_all(read_at: Time.current, updated_at: Time.current)
    redirect_back fallback_location: reader_path,
      notice: count.positive? ? "#{helpers.pluralize(count, "item")} marked read." : "Nothing left to mark read."
  end

  private
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
