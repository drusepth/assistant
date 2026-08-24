module Recipes
  # The instance-to-instance envelope (D-share-link, RECIPES_PLAN §5): a
  # recipe or a whole book, as plain JSON, so a share link sent to someone
  # who *also* runs this app is one paste (or one link) away from being
  # theirs — no model call, no re-typing, no account on anybody's box.
  #
  # Everything here is treated as hostile input even though a person pasted
  # it deliberately: types are coerced, lengths capped, counts bounded, and
  # only the fields listed below are ever read.
  module Payload
    FORMAT = "assistant-recipe".freeze
    VERSION = 1
    MAX_RECIPES = 200
    MAX_TEXT = 20_000
    MAX_LINE = 500

    Parsed = Data.define(:book_title, :book_description, :recipes)

    module_function

    def for_recipe(recipe)
      { "format" => FORMAT, "version" => VERSION, "recipe" => recipe_hash(recipe) }
    end

    def for_book(book, recipes)
      {
        "format" => FORMAT, "version" => VERSION,
        "book" => { "title" => book.title, "description" => book.description },
        "recipes" => recipes.map { |recipe| recipe_hash(recipe) }
      }
    end

    def recipe_hash(recipe)
      {
        "title" => recipe.title,
        "description" => recipe.description,
        "servings" => recipe.servings,
        "prep_minutes" => recipe.prep_minutes,
        "cook_minutes" => recipe.cook_minutes,
        # Raw lines, not parsed rows: the receiving instance runs its own
        # parser, so both ends stay on one implementation of the arithmetic.
        "ingredients" => recipe.recipe_ingredients.map(&:raw),
        "directions" => recipe.directions,
        "notes" => recipe.notes,
        "source_name" => recipe.source_name,
        "source_url" => recipe.source_url
      }.compact
    end

    # Text → Parsed, or nil when this isn't one of ours. Never raises.
    def parse(text)
      return nil if text.blank? || !text.lstrip.start_with?("{")

      document = JSON.parse(text)
      return nil unless document.is_a?(Hash) && document["format"] == FORMAT

      recipes = Array(document["recipes"]).presence || [ document["recipe"] ].compact
      attributes = recipes.first(MAX_RECIPES).filter_map { |row| recipe_attributes(row) }
      return nil if attributes.empty?

      Parsed.new(
        book_title: string(document.dig("book", "title"), 200),
        book_description: string(document.dig("book", "description"), MAX_TEXT),
        recipes: attributes
      )
    rescue JSON::ParserError
      nil
    end

    def recipe_attributes(row)
      return nil unless row.is_a?(Hash)

      title = string(row["title"], 200)
      return nil if title.blank?

      {
        title: title,
        description: string(row["description"], MAX_TEXT),
        servings: integer(row["servings"]),
        prep_minutes: integer(row["prep_minutes"]),
        cook_minutes: integer(row["cook_minutes"]),
        ingredients_text: text_lines(row["ingredients"]),
        directions: text_lines(row["directions"]),
        notes: string(row["notes"], MAX_TEXT),
        source_name: string(row["source_name"], 100),
        source_url: url(row["source_url"])
      }.compact
    end

    def string(value, limit)
      return nil unless value.is_a?(String)

      value.strip.presence&.truncate(limit)
    end

    def integer(value)
      number = value.to_s[/\d+/].to_i
      number.positive? && number < 100_000 ? number : nil
    end

    def text_lines(value)
      lines = Array(value.is_a?(String) ? value.split("\n") : value)
      lines.filter_map { |line| string(line, MAX_LINE) }.join("\n").presence&.truncate(MAX_TEXT)
    end

    # A link is the one field that gets rendered as a link, so it may only
    # ever be http(s).
    def url(value)
      candidate = string(value, 2_000)
      candidate if candidate&.match?(%r{\Ahttps?://\S+\z})
    end
  end
end
