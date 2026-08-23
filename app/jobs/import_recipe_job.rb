# Paste-import (RECIPES_PLAN §5.1), on the AnalyzeDocumentJob pattern: the
# recipe row exists from the moment the paste lands, this fills it in, and a
# failure is written down where the cook can see it and retry — never a
# silent nothing.
#
# Both leashes stay app-side (D-career-web): if the user gave a link, *this*
# fetches it through Web::Fetch (SSRF-guarded, size-capped) and hands the
# model text. The model never drives a connection.
class ImportRecipeJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  SOURCE_LIMIT = 60_000
  ATTRIBUTES = %i[ title description servings prep_minutes cook_minutes
    ingredients_text directions notes source_name ].freeze

  def perform(recipe)
    recipe.update!(import_status: :processing)
    text = source_text(recipe)
    raise Llm::Error, "There was no text to read." if text.blank?

    result = extract(recipe, text)
    attributes = result.to_h.slice(*ATTRIBUTES).compact_blank
    recipe.assign_attributes(attributes)
    recipe.title = attributes[:title].presence || recipe.title.presence || "Imported recipe"
    recipe.import_status = :imported
    recipe.import_error = nil
    recipe.save!
    # Only now is there a recipe to read: at paste time the row was a
    # placeholder title and a blob of page.
    recipe.enqueue_auto_sort!
  rescue Llm::Error, Web::Fetch::Error => e
    raise if will_retry?(e)

    recipe.update!(import_status: :failed, import_error: e.message)
    record_failure(e, user: recipe.user, context: { recipe_id: recipe.id })
  rescue StandardError => e
    recipe.update!(import_status: :failed, import_error: "Something went wrong reading that — try again.")
    record_failure(e, user: recipe.user, context: { recipe_id: recipe.id })
    raise
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to(recipe.user, :recipes) if recipe.persisted?
  end

  private
    # A pasted blob is already here; a link is fetched once and kept, so a
    # retry doesn't ask the user to go find the page again.
    def source_text(recipe)
      return recipe.import_source if recipe.import_source.present?
      return nil if recipe.source_url.blank?

      page = Web::Fetch.text(recipe.source_url)
      recipe.update!(import_source: page.text.to_s.truncate(SOURCE_LIMIT),
        title: recipe.title.presence || page.title.to_s.truncate(200))
      recipe.import_source
    end

    # With a model, the model finds the recipe in the memoir. Without one,
    # the deterministic splitter still finds the seams on most pages — the
    # feature degrades, it doesn't disappear (the D13 AI-lite posture).
    def extract(recipe, text)
      profile = recipe.importable_profile
      return Recipes::Split.call(text) if profile.nil?

      Recipes::Import.new(text: text, profile: profile, source_url: recipe.source_url).call
    end
end
