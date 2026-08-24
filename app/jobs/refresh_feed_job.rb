# Fetches one feed (D-feed-reader). Enqueued by the scheduled sweep, when a
# feed is first added, by an OPML import, and by the reader's own "Check"
# buttons — which hand the work here rather than doing it in the request,
# because a stranger's server that hangs must never hold a web worker.
#
# A fetch failure is a *condition*, not an exception: a stranger's server
# being down is the normal weather of an RSS reader, so Feeds::Refresh
# records it on the feed's row (where the reader shows it) and this job
# returns quietly rather than filling the failed-jobs table with the
# internet's ordinary rudeness.
class RefreshFeedJob < ApplicationJob
  queue_as :default

  def perform(feed)
    return unless feed.active?

    result = Feeds::Refresh.call(feed)
    # Only when something actually moved: the page the user is looking at
    # morphs in place, so a broadcast per polite no-op check would be a
    # page-refresh every fifteen minutes for nothing.
    broadcast(feed) if result.changed? || !result.ok?
  end

  private
    def broadcast(feed)
      Turbo::StreamsChannel.broadcast_refresh_to(feed.user, :reader)
    end
end
