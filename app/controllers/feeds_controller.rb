# Subscriptions (D-feed-reader): paste any address, get a feed. Discovery
# does the work of finding the feed behind a site, so the user never has to
# hunt for the orange icon — the friction that made this format feel like a
# format for hobbyists.
#
# Adding a feed fetches twice on purpose: once, synchronously, to prove the
# address is a feed and to name it (a subscription that silently fails to
# exist is worse than a slow form), then again in the background to fill the
# river.
class FeedsController < ApplicationController
  before_action :set_feed, only: %i[ edit update destroy refresh ]

  def index
    @feeds = Current.user.feeds.includes(:sections).order(:created_at)
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
      redirect_to feeds_path, notice: "#{@feed.display_title} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @feed.destroy!
    redirect_to feeds_path, notice: "Unfollowed #{@feed.display_title}. Its items are gone too."
  end

  def refresh
    Feeds::Refresh.call(@feed)
    redirect_back fallback_location: feeds_path,
      notice: @feed.healthy? ? "#{@feed.display_title} is up to date." : "#{@feed.display_title}: #{@feed.last_error}"
  end

  def refresh_all
    Current.user.feeds.active.find_each { |feed| RefreshFeedJob.perform_later(feed) }
    redirect_back fallback_location: feeds_path, notice: "Checking your feeds — new items appear as they arrive."
  end

  private
    def set_feed
      @feed = Current.user.feeds.find(params[:id])
    end

    def feed_params
      params.expect(feed: [ :url, :label, :active, section_ids: [] ])
    end
end
