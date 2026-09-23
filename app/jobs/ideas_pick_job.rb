# Tonight's pick (D-food-suggestions), off the request: the ideas page shows
# the ranked lists at once and the pick arrives over Turbo when the model
# has answered. Cached against the kitchen's state, so it's asked again only
# when something in the kitchen changes.
class IdeasPickJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  # What the pick depends on — what's in, the recipes, and the diners — and
  # not the list: ticking off milk shouldn't re-ask the model for dinner.
  def self.cache_key(kitchen, viewer)
    [ "ideas-pick", kitchen.id, viewer.id, kitchen.pantry_items.count, kitchen.pantry_items.maximum(:updated_at).to_i,
      kitchen.diners.maximum(:updated_at).to_i, Recipe.visible_to(viewer).maximum(:updated_at).to_i ]
  end

  # The pick for this state of the kitchen: a hash once answered, :pending
  # while it's being asked (asking once), nil with no model to ask.
  def self.fetch(kitchen, viewer)
    return nil unless Foods::Catalog.new(kitchen).model?

    key = cache_key(kitchen, viewer)
    cached = Rails.cache.read(key)
    return cached if cached.is_a?(Hash)
    return :pending if cached == "pending"

    Rails.cache.write(key, "pending", expires_in: 5.minutes)
    perform_later(kitchen, viewer)
    :pending
  end

  def perform(kitchen, viewer)
    profile = Foods::Catalog.new(kitchen).profile
    return unless profile

    ideas = Kitchens::Ideas.new(kitchen, viewer)
    result = Kitchens::IdeasPick.new(ideas, profile: profile, diet_notes: kitchen.diners.filter_map(&:diet_note)).call
    Rails.cache.write(self.class.cache_key(kitchen, viewer), pick_payload(result), expires_in: 12.hours)
    Turbo::StreamsChannel.broadcast_refresh_to(kitchen)
  rescue Llm::Error => e
    raise if will_retry?(e)

    Rails.cache.write(self.class.cache_key(kitchen, viewer), { "none" => true }, expires_in: 1.hour)
    record_failure(e, user: viewer, context: { kitchen_id: kitchen.id })
  end

  private
    def pick_payload(result)
      return { "none" => true } if result.nil?

      { "recipe_id" => result.recipe.id, "reason" => result.reason, "swaps" => result.swaps }
    end
end
