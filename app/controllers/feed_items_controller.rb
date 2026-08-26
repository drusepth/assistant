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

  # "This isn't Birding" (D-story-matching): the correcting verb on a story
  # the model routed into a hobby its feed isn't filed under. It leaves the
  # row's place with a send-off and an Undo, like every other verb here that
  # takes something off a list — and the rejection becomes an example the
  # next batch is shown.
  def reject = act { @rejected = reject_routing }
  def unreject = act { restore_routing }

  private
    # Items are reachable only through the user's own feeds.
    def set_item
      @item = FeedItem.where(feed: Current.user.feeds).find(params[:id])
    end

    def act
      yield
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(row_id, partial: row_partial, locals: row_locals)
        end
        format.html { redirect_back fallback_location: reader_path }
      end
    end

    # `from=expand` is a row that marked itself read *by being opened* rather
    # than by being left. It stays where it is (no send-off line), and it
    # comes back open — otherwise the re-render its own mark-read triggered
    # would shut the thing the reader just opened.
    def expanded? = params[:from] == "expand"

    # The routing named in the params, if this user really has one there.
    # `routings` is the live scope, so a second click on a row somebody left
    # open finds nothing and changes nothing.
    def reject_routing
      routing = @item.routings.find_by(section_id: params[:section_id])
      routing&.reject!
      routing
    end

    def restore_routing
      routing = StoryRouting.rejected.find_by(feed_item_id: @item.id, section_id: params[:section_id])
      routing&.update!(rejected_at: nil)
    end

    def row_locals
      locals = { item: @item }
      locals[:filter] = params[:from] unless hub? || expanded?
      locals[:expanded] = true if expanded?
      locals[:routing] = @rejected if @rejected
      # The lens the row was being read under, so the re-rendered row knows
      # which chips repeat the page it is on.
      locals[:section] = lens if lens && !@rejected
      locals
    end

    def lens
      return nil if params[:section_id].blank?

      @lens ||= Section.find_by(id: params[:section_id])
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
      # A rejected row is no longer part of the river it is sitting in, so
      # it gets the same send-off a mark-read leaves rather than a row that
      # silently lost its tell.
      return "reader/unrouted" if @rejected

      @item.read? && params[:from] == "unread" ? "reader/dismissed" : "reader/item"
    end
end
