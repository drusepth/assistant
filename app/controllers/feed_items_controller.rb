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

  # A row marked read while you are *looking at the unread list* should
  # leave it — otherwise "unread" is a lie and the only way to clear a
  # screen is Mark all read. It leaves behind a line its own height saying
  # what went, with an Undo, so nothing vanishes without a way back.
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
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(row_id, partial: row_partial, locals: { item: @item })
        end
        format.html { redirect_back fallback_location: reader_path }
      end
    end

    # The same verbs act on two surfaces now: the river, and the hobby cards
    # on the Hobbies hub (D-hobby-feeds). `surface` says which row asked, so
    # one code path re-renders the right shape into the right id — a river
    # row rendered into a hub card would be a full-width list line inside a
    # three-line taste.
    def hub? = params[:surface] == "hub"

    def row_id = hub? ? helpers.dom_id(@item, :hub) : helpers.dom_id(@item)

    # `from` is the filter the row was rendered under, so the row knows
    # whether it still belongs where it is.
    def row_partial
      return "sections/hobby_story" if hub?

      @item.read? && params[:from] == "unread" ? "reader/dismissed" : "reader/item"
    end
end
