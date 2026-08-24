# The river (D-feed-reader): everything the user's feeds carried, in the
# order that suits how they read — Interesting (hobby-aware decay, see
# Feeds::Rank) or Newest, filtered to unread, saved, or everything, and
# narrowed to one hobby lens or one feed.
#
# Google Reader's shape, with its one real omission fixed: it never knew
# what you were into. This one does, because the household already told the
# app what its hobbies are, and because the ranking is the user's own words
# rather than a stranger's engagement model.
class ReaderController < ApplicationController
  def index
    @river = Feeds::River.new(
      Current.user, filter: params[:filter] || "unread", sort: params[:sort] || "interesting",
      section: hobby_lens, feed: own_feed_id
    )
    @page = @river.page(offset: params[:offset].to_i.clamp(0, Feeds::River::WINDOW))
    @feeds = Current.user.feeds.includes(:sections).order(:created_at)
    @lenses = Section.find_by(slug: "hobbies")&.children&.where(id: @feeds.flat_map(&:section_ids))&.order(:name) || []
    @unread_counts = FeedItem.where(feed: @feeds).unread.group(:feed_id).count
    @interest = Feeds::Interest.for(Current.user)
  end

  # "Mark everything I'm looking at as read" — the verb that keeps a river
  # from becoming a guilt pile. Scoped to the current filters, never to
  # every feed the user has.
  def read_all
    river = Feeds::River.new(
      Current.user, filter: "unread", sort: "new", section: hobby_lens, feed: own_feed_id
    )
    # By id rather than on the scope: the river's scope carries a LIMIT, and
    # SQLite is usually built without UPDATE … LIMIT.
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
