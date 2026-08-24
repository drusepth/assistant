module Recipes
  # The deterministic half of paste-import (RECIPES_PLAN §5.1): find the
  # recipe inside a pasted page. Recipe sites bury four lines of method
  # under nine hundred words of memoir, and the headings that separate them
  # are remarkably consistent — so plain code can usually find the seam.
  #
  # It runs in two roles: on an instance with no model configured it *is*
  # the import, and where a model exists it still trims the page first so
  # the prompt spends its budget on the recipe rather than the essay.
  module Split
    INGREDIENT_HEADING = /\A(ingredients|you(?:'|’)?ll need|what you need|shopping list)\b[:\s]*\z/i
    METHOD_HEADING = /\A(method|directions|instructions|steps|preparation|how to make it)\b[:\s]*\z/i
    # Everything after the recipe proper: the comment mine and the SEO tail.
    TAIL_HEADING = /\A(notes?|nutrition|comments?|reviews?|you might also like|related recipes|leave a (?:reply|comment))\b[:\s]*\z/i

    Result = Data.define(:title, :ingredients_text, :directions, :notes)

    module_function

    def call(text)
      lines = text.to_s.gsub("\r\n", "\n").split("\n").map(&:strip)
      ingredients_at = lines.index { |line| line.match?(INGREDIENT_HEADING) }
      method_at = lines.index { |line| line.match?(METHOD_HEADING) }

      # Without both seams there is nothing to be confident about: hand the
      # whole thing back as the ingredients paste and let the human split it.
      if ingredients_at.nil? || method_at.nil? || method_at <= ingredients_at
        return Result.new(title: title_from(lines), ingredients_text: squeeze(lines), directions: nil, notes: nil)
      end

      tail_at = lines.each_index.find { |index| index > method_at && lines[index].match?(TAIL_HEADING) }
      method_lines = lines[(method_at + 1)...(tail_at || lines.length)]

      Result.new(
        title: title_from(lines.first(ingredients_at)),
        ingredients_text: squeeze(lines[(ingredients_at + 1)...method_at]),
        directions: squeeze(method_lines),
        notes: tail_at ? squeeze(lines[(tail_at + 1)..])&.truncate(1_000) : nil
      )
    end

    # The first line with the shape of a name: real words, not a nav crumb,
    # not a sentence.
    def title_from(lines)
      lines.find { |line| line.length.between?(3, 90) && line.split.size.between?(1, 12) && !line.end_with?(".") }
    end

    def squeeze(lines)
      Array(lines).map(&:strip).reject(&:blank?).join("\n").presence
    end
  end
end
