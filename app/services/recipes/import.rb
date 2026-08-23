module Recipes
  # Paste-import (RECIPES_PLAN §5.1): a wall of pasted text — or the text of
  # a page the app fetched — becomes a filled-in recipe the cook reviews.
  #
  # The division of labour is the point. The model does the job only a model
  # can do: find the recipe inside the memoir and re-emit it as clean lines.
  # The *numbers* are then read by the deterministic parser exactly as if
  # they'd been typed, so quantities, units and match keys come from code on
  # every path — an imported recipe and a hand-typed one are the same object,
  # with no second, softer parser to keep in step.
  class Import
    PROMPT_TEXT_LIMIT = 14_000
    MAX_INGREDIENTS = 80
    MAX_STEPS = 40

    Result = Data.define(:title, :description, :servings, :prep_minutes, :cook_minutes,
      :ingredients_text, :directions, :notes, :source_name)

    def initialize(text:, profile:, source_url: nil)
      @text = text.to_s
      @profile = profile
      @source_url = source_url
    end

    def call
      response = @profile.client.chat(messages, json: true)
      raise Llm::Error, "The model didn't find a recipe in that." if response["title"].blank?

      Result.new(
        title: string(response["title"], 200),
        description: string(response["description"], 500),
        servings: positive_integer(response["servings"]),
        prep_minutes: positive_integer(response["prep_minutes"]),
        cook_minutes: positive_integer(response["cook_minutes"]),
        ingredients_text: lines(response["ingredients"], MAX_INGREDIENTS),
        directions: lines(response["directions"], MAX_STEPS),
        notes: string(response["notes"], 2_000),
        source_name: string(response["source_name"], 100)
      )
    end

    private
      def messages
        [ { role: "system", content: system_prompt }, { role: "user", content: user_prompt } ]
      end

      def system_prompt
        <<~PROMPT
          You are the recipe-import feature of a private, self-hosted life assistant.
          The user has pasted a page that contains a recipe, usually surrounded by an
          essay, navigation, adverts, and comments. Return only the recipe.

          Respond with a JSON object:
          {"title": "...", "description": "...", "servings": 4, "prep_minutes": 10,
           "cook_minutes": 30, "ingredients": ["...", ...], "directions": ["...", ...],
           "notes": "...", "source_name": "..."}

          Rules:
          - "ingredients" is one string per line, written the way a cook writes them —
            quantity, unit, item, then any preparation after a comma:
            "200 g plain flour", "2 large onions, finely chopped", "salt to taste".
            Keep the page's own units and amounts exactly; never convert, never round,
            never invent an amount that isn't stated.
            Keep component dividers as their own line, ending in a colon: "For the sauce:".
          - "directions" is one string per step, in order, without step numbers.
          - "description" is at most two sentences, and only if the page gives one worth
            keeping. "notes" is for genuine cook's tips (make-ahead, substitutions,
            storage) — not for the author's life story, and not for comments.
          - "source_name" is the site or cookbook the recipe came from, if the page says.
          - Omit any field the page doesn't state rather than guessing. Never write a
            placeholder like "unknown" or "N/A".
          - If the page contains no recipe at all, return {"title": ""}.
        PROMPT
      end

      def user_prompt
        parts = []
        parts << "The page was fetched from: #{@source_url}" if @source_url.present?
        parts << "Page text:\n#{trimmed_text}"
        parts.join("\n\n")
      end

      # Send the deterministic split's view whenever it found both seams: it
      # drops the essay and the comment mine for free, which leaves the
      # budget for the recipe itself on a long page. When it didn't find
      # them, the model gets the whole page — that's the case it's for.
      def trimmed_text
        split = Split.call(@text)
        found_both = split.directions.present? && split.ingredients_text.present?
        text = found_both ? [ split.title, split.ingredients_text, split.directions ].compact.join("\n\n") : @text
        text.truncate(PROMPT_TEXT_LIMIT)
      end

      def string(value, limit)
        return nil unless value.is_a?(String)

        value.strip.presence&.truncate(limit)
      end

      def positive_integer(value)
        number = value.to_s[/\d+/].to_i
        number.positive? && number < 100_000 ? number : nil
      end

      def lines(value, limit)
        list = Array(value).filter_map { |line| line.to_s.strip.presence }.first(limit)
        list.join("\n").presence
      end
  end
end
