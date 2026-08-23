class CategorizeRecipeJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(recipe)
    profile = recipe.auto_sort_profile
    return unless profile
    return if recipe.sections.any? # the user tagged it themselves — don't second-guess

    recipe.sections = Recipes::Categorize.new(recipe: recipe, profile: profile).call.sections
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Best-effort: once the model is out of chances the recipe just stays
    # unfiled, and the cook can tag it from the edit form.
    record_failure(e, user: recipe.user, context: { recipe_id: recipe.id })
  end
end
