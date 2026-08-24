# The per-item verbs (D-feed-reader): read, save, vote. Every one of them
# re-renders just that item's row over Turbo, because a reader is a page you
# act on twenty times in a sitting and a full reload after each is what made
# self-hosted readers feel like homework.
#
# The vote is the reader's only learning signal, and it is honest about what
# it does: it re-weights *your* ranking (Feeds::Interest), nothing leaves the
# instance, and a downvoted item sinks rather than disappearing.
class FeedItemsController < ApplicationController
  before_action :set_item

  def read = act { @item.mark_read! }
  def unread = act { @item.mark_unread! }
  def save = act { @item.save_item! }
  def unsave = act { @item.unsave! }
  def vote = act { @item.vote!(params[:direction]) }

  private
    # Items are reachable only through the user's own feeds — the river
    # never joins across household members (Q-feed-sharing).
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
