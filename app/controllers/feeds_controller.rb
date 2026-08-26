# Subscriptions (D-feed-reader): paste any address, get a feed. Discovery
# does the work of finding the feed behind a site, so the user never has to
# hunt for the orange icon — the friction that made this format feel like a
# format for hobbyists.
#
# Two fetch postures, and the difference is who is waiting. Adding a feed
# fetches *now*, on short timeouts, because a subscription that silently
# fails to exist is worse than a slow form. Everything else — "Check now",
# "Check all", an OPML import — hands the work to a job: a stranger's server
# that hangs must never hold a web worker for half a minute.
class FeedsController < ApplicationController
  before_action :set_feed, only: %i[ edit update destroy refresh refile ]

  def index
    @feeds = Current.user.feeds.includes(:sections).order(:created_at)
    # The hobbies a stray feed can be filed under, and how many strays there
    # are (D-hobby-feeds) — the catch-all itself is never an option, since
    # it is where a feed lands rather than somewhere to put one.
    @lenses = Hobbies::MapFeeds.askable_lenses
    unfiled = @feeds.to_a.select { |feed| helpers.feed_unfiled?(feed) }
    @unfiled_count = unfiled.size
    @feeds = unfiled if params[:unfiled]
    @unread_counts = FeedItem.where(feed: @feeds).unread.group(:feed_id).count
    @feed = Current.user.feeds.new
  end

  def create
    @feed = Current.user.feeds.new(feed_params.except(:url))
    found = Feeds::Discover.call(feed_params[:url])
    @feed.assign_attributes(
      url: found.url, kind: found.parsed.kind, title: found.parsed.title,
      description: found.parsed.description, site_url: found.parsed.site_url
    )

    if @feed.save
      RefreshFeedJob.perform_later(@feed)
      # Which hobbies is this? Asked in a job, or not at all on an instance
      # with no model — either way the feed has a home before this request
      # ends (D-hobby-feeds).
      Feeds::Filing.call(@feed)
      redirect_to return_to_path(feeds_path), notice: "Following #{@feed.display_title}."
    else
      redirect_to return_to_path(feeds_path), alert: @feed.errors.full_messages.to_sentence
    end
  rescue Feeds::Discover::Error => e
    redirect_to return_to_path(feeds_path), alert: e.message
  end

  def edit
  end

  def update
    if @feed.update(feed_params.except(:url))
      # `return_to` because this is also the filing picker on the feed list,
      # and a correction made in a filtered list should hand that list back
      # rather than the whole one.
      redirect_to return_to_path(feeds_path), notice: "#{@feed.display_title} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @feed.destroy!
    redirect_to feeds_path, notice: "Unfollowed #{@feed.display_title}. Its items are gone too."
  end

  # Enqueued, not fetched here: the row updates itself over Turbo when the
  # job lands (RefreshFeedJob broadcasts), so nobody watches a spinner and
  # no thread is hostage to somebody else's timeout.
  def refresh
    RefreshFeedJob.perform_later(@feed)
    redirect_back fallback_location: feeds_path, notice: "Checking #{@feed.display_title}…"
  end

  # "Re-file": ask the model again about a feed whose hobbies look wrong —
  # or about one that was followed before a model was configured.
  def refile
    notice = if Feeds::Filing.refile(@feed)
      "Re-filing #{@feed.display_title}…"
    else
      "No model is configured, so feeds are filed by hand — pick a hobby below."
    end
    redirect_back fallback_location: feeds_path, notice: notice
  end

  def refresh_all
    Current.user.feeds.active.find_each { |feed| RefreshFeedJob.perform_later(feed) }
    redirect_back fallback_location: feeds_path, notice: "Checking your feeds — new items appear as they arrive."
  end

  # The reading list, in the format every reader since 2000 agrees on.
  def export
    send_data Feeds::Opml.export(Current.user),
      filename: "feeds-#{Date.current.iso8601}.opml", type: "text/x-opml", disposition: "attachment"
  end

  def import
    file = params[:file]
    return redirect_to feeds_path, alert: "Choose an OPML file to import." if file.blank?

    result = Feeds::Opml.import(Current.user, file.read, create_lenses: params[:create_lenses] == "1")
    return redirect_to feeds_path, alert: result.error unless result.ok?

    redirect_to feeds_path, notice: import_notice(result)
  end

  # The starter shelf: whatever the user ticked, through the ordinary OPML
  # path. Nothing here is followed unless it was ticked (D-hobby-feeds §7.1).
  def starters
    # A form with nothing ticked posts an empty string, not an empty list.
    urls = Array(params[:urls]).map(&:to_s).reject(&:blank?)
    return redirect_to feeds_path, alert: "Pick at least one to follow." if urls.empty?

    result = Feeds::Starters.import(Current.user, urls, create_lenses: params[:create_lenses] == "1")
    return redirect_to feeds_path, alert: result.error unless result.ok?

    # Back where the shelf was — it appears on the reader, the feed list and
    # the Hobbies hub, and landing somewhere else after ticking two boxes is
    # its own small betrayal.
    redirect_to return_to_path(feeds_path), notice: import_notice(result)
  end

  private
    def set_feed
      @feed = Current.user.feeds.find(params[:id])
    end


    def import_notice(result)
      parts = [ "#{helpers.pluralize(result.added, "feed")} added" ]
      parts << "#{result.skipped} already followed or unreadable" if result.skipped.positive?
      parts << "filed under #{result.lenses.to_sentence}" if result.lenses.any?
      "#{parts.join(", ")}. They're being checked now."
    end

    def feed_params
      params.expect(feed: [ :url, :label, :active, section_ids: [] ])
    end
end
