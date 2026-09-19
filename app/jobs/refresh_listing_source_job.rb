# Fetches one listing source (D-listing-feeds). Enqueued by the scheduled
# sweep, when a source is first followed, and by the "Check" verb — never
# run in the request, because a stranger's server that hangs must never
# hold a web worker.
#
# A fetch failure is a condition, not an exception: Listings::Refresh
# records it on the source's row, where the Places page shows it, and this
# job returns quietly. Matching the new arrivals is a model call and lives
# in its own job (D-event-radar); it is asked for here so a refresh that
# found something is followed by the judgment about it.
class RefreshListingSourceJob < ApplicationJob
  queue_as :default

  def perform(source)
    return unless source.active?

    result = Listings::Refresh.call(source)
    Radar::Match.enqueue(source.place.user) if result.added.positive?
  end
end
