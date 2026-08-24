# The per-item verbs (D-feed-reader): read, and keep. Each one re-renders
# just that item's row over Turbo, because a reader is a page you act on
# twenty times in a sitting and a full reload after each is what made
# self-hosted readers feel like homework.
#
# That is the whole list. There is no vote and no rating: this is one
# person's reading list, and the only questions it asks are "have you seen
# this" and "do you want to keep it".
class FeedItemsController < ApplicationController
  before_action :set_item

  def read = act { @item.mark_read! }
  def unread = act { @item.mark_unread! }
  def save = act { @item.save_item! }
  def unsave = act { @item.unsave! }

  private
    # Items are reachable only through the user's own feeds.
    def set_item
      @item = FeedItem.where(feed: Current.user.feeds).find(params[:id])
    end

    def act
      yield
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@item, partial: "reader/item", locals: { item: @item }) }
        format.html { redirect_back fallback_location: reader_path }
      end
    end
end
