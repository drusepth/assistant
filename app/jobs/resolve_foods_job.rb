# Files a kitchen's new wordings onto foods (D-food-catalog), then tells
# every open kitchen page, so the list regroups by aisle while you look at it.
#
# Limited per run and re-enqueued while there is more, so a first visit from
# a household with 400 recipes files them over a few calls rather than one
# enormous one.
class ResolveFoodsJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def self.enqueue(kitchen) = perform_later(kitchen)

  # The nightly catch-up: recipes saved or edited since, in every kitchen.
  def self.sweep
    Kitchen.find_each { |kitchen| enqueue(kitchen) if Foods::Catalog.new(kitchen).unresolved? }
  end

  def perform(kitchen)
    catalog = Foods::Catalog.new(kitchen)
    filed = catalog.resolve!
    kitchen.broadcast_change if filed.positive?
    self.class.perform_later(kitchen) if filed >= Foods::Catalog::MAX_PER_RUN && catalog.unresolved?
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Out of chances: the lines stay unfiled and the next add or visit tries
    # again. Nothing is filed on a guess.
    record_failure(e, user: kitchen.user, context: { kitchen_id: kitchen.id })
  end
end
