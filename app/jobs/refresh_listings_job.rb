# The scheduled sweep for listing sources (D-listing-feeds): every source
# past its own interval gets a fetch. The SQL scope is the cheap prefilter;
# each source's `due_for_refresh?` applies the backoff a failing one has
# earned and the daily interval a place nobody opens has earned.
class RefreshListingsJob < ApplicationJob
  queue_as :default

  def self.refresh_due
    ListingSource.due_for_refresh.includes(:place).find_each do |source|
      RefreshListingSourceJob.perform_later(source) if source.due_for_refresh?
    end
  end

  def perform = self.class.refresh_due
end
