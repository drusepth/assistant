# Fetches one feed (D-feed-reader). Enqueued by the scheduled sweep, when a
# feed is first added, and by the reader's own "Refresh" button.
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

    Feeds::Refresh.call(feed)
  end
end
