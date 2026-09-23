module Recipes
  # Auto-sorting for recipes (D16): capture is a paste, so the form asks for
  # the recipe and nothing else — the household's model reads what was typed
  # and files it into sections. A recipe carries plenty of signal for this
  # (the low-sodium ones are Health, the sourdough is Hobbies · Baking,
  # Grandma's is People), which is exactly why asking the cook to pick from
  # the whole taxonomy was the wrong trade.
  class Categorize
    MAX_SECTIONS = 3
    # Enough of the list for the model to tell a cake from a stew without
    # posting a whole cookbook to the provider.
    INGREDIENT_LIMIT = 30
    TEXT_LIMIT = 500

    Result = Data.define(:sections)

    def initialize(recipe:, profile:)
      @recipe = recipe
      @profile = profile
    end

    def call
      response = @profile.client.chat(messages, json: true)

      Result.new(sections: Llm::Taxonomy.match(response["sections"], limit: MAX_SECTIONS))
    end

    private
      def messages
        [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ]
      end

      def system_prompt
        <<~PROMPT
          You are the recipe-filing feature of a private, self-hosted life assistant.
          The user saves a recipe by pasting it in; you file it into the sections it
          belongs to, so they never have to tag anything themselves. Respond with a
          JSON object: {"sections": ["slug", ...]}.
          Choose at most #{MAX_SECTIONS} sections, only from the provided list, ordered by
          relevance; choose none if nothing clearly fits.
          File on what the recipe is actually about — a dietary angle is Health, a
          craft like bread or brewing is the matching hobby, a recipe attributed to
          someone belongs with People. Do not file every recipe under the same
          section just because it is food — every recipe already appears on the
          food section's page, so choose "food" only when nothing else fits.
        PROMPT
      end

      def user_prompt
        parts = [ "Recipe: #{@recipe.title}" ]
        parts << "Description: #{@recipe.description.to_s.truncate(TEXT_LIMIT)}" if @recipe.description.present?
        parts << "From: #{@recipe.source_name}" if @recipe.source_name.present?
        parts << "Ingredients:\n#{ingredients}" if ingredients.present?
        parts << "Cook's notes: #{@recipe.notes.to_s.truncate(TEXT_LIMIT)}" if @recipe.notes.present?
        parts << "Available sections (slug — meaning):\n#{Llm::Taxonomy.listing}"
        parts.join("\n\n")
      end

      def ingredients
        @ingredients ||= @recipe.recipe_ingredients.limit(INGREDIENT_LIMIT).map(&:raw).join("\n")
      end
  end
end
