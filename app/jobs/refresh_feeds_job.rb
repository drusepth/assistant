# The scheduled sweep (D-feed-reader): every feed that has gone past its own
# interval gets a fetch. The SQL scope is the cheap prefilter; each feed's
# `due_for_refresh?` applies the backoff a failing feed has earned and the
# longer interval a feed nobody reads any more has earned.
#
# Politeness is the design constraint here — this is the one part of the app
# that makes repeated requests to other people's servers on a timer, and a
# self-hosted instance with a dozen households behind it should be
# indistinguishable from one person with a browser.
class RefreshFeedsJob < ApplicationJob
  queue_as :default

  def self.refresh_due
    Feed.due_for_refresh.find_each do |feed|
      RefreshFeedJob.perform_later(feed) if feed.due_for_refresh?
    end
  end

  def perform = self.class.refresh_due
end
