module Recipes
  # Kitchen numbers, both directions: text like "1 1/2", "1½", or "2-3"
  # becomes a decimal, and a decimal becomes something a person would write
  # on a card. Scaling a recipe is arithmetic, so this is where the
  # arithmetic is allowed to look human (D-recipe-primitive).
  module Quantity
    UNICODE_FRACTIONS = {
      "¼" => 0.25r, "½" => 0.5r, "¾" => 0.75r, "⅓" => 1r / 3, "⅔" => 2r / 3,
      "⅕" => 0.2r, "⅖" => 0.4r, "⅗" => 0.6r, "⅘" => 0.8r,
      "⅙" => 1r / 6, "⅚" => 5r / 6, "⅛" => 0.125r, "⅜" => 0.375r,
      "⅝" => 0.625r, "⅞" => 0.875r
    }.freeze

    # Written back out at eighth-of-a-unit resolution — the granularity a
    # measuring cup actually has.
    DISPLAY_FRACTIONS = {
      Rational(1, 8) => "⅛", Rational(1, 4) => "¼", Rational(1, 3) => "⅓",
      Rational(3, 8) => "⅜", Rational(1, 2) => "½", Rational(5, 8) => "⅝",
      Rational(2, 3) => "⅔", Rational(3, 4) => "¾", Rational(7, 8) => "⅞"
    }.freeze

    TOLERANCE = 0.02

    module_function

    # The leading amount of an ingredient line, as [value, rest]. Handles
    # "2", "1.5", "1 1/2", "3/4", "1½", "½", and ranges ("2-3" → the low
    # end, because a shopping list has to name one number). Returns
    # [nil, line] when the line doesn't start with a quantity at all —
    # "salt to taste" is a perfectly good ingredient.
    def parse(text)
      rest = text.to_s.strip
      total = nil

      if (match = fraction_match(rest))
        # A bare fraction: "3/4 cup sugar".
        total = match.first
        rest = match.last
      elsif (match = rest.match(/\A(\d+(?:[.,]\d+)?)\s*/))
        total = match[1].tr(",", ".").to_r
        rest = match.post_match
        # A range ("2-3 apples", "2 to 3"): keep the low end, because a
        # shopping list has to name one number.
        if (range = rest.match(%r{\A(?:-|–|—|to)\s*\d+(?:[./]\d+)?\s*}))
          rest = range.post_match
        end
        # The tail of a mixed number: "1 1/2", "2¼".
        if (mixed = fraction_match(rest))
          total += mixed.first
          rest = mixed.last
        end
      end

      [ total&.to_f, rest ]
    end

    # A leading fraction, vulgar or written: [value, rest], or nil.
    def fraction_match(text)
      if (match = text.match(%r{\A(\d+)\s*/\s*(\d+)\s*})) && match[2].to_i.positive?
        [ Rational(match[1].to_i, match[2].to_i), match.post_match ]
      elsif (match = text.match(/\A(#{Regexp.union(UNICODE_FRACTIONS.keys)})\s*/))
        [ UNICODE_FRACTIONS.fetch(match[1]), match.post_match ]
      end
    end

    # 1.5 → "1½", 0.75 → "¾", 2.0 → "2", 0.4 → "0.4" (no lie about being a
    # nice fraction).
    def format(value)
      return nil if value.nil?

      whole = value.floor
      remainder = value - whole
      return whole.to_s if remainder < TOLERANCE

      fraction = DISPLAY_FRACTIONS.find { |ratio, _| (remainder - ratio).abs < TOLERANCE }
      return "#{whole.zero? ? "" : whole}#{fraction.last}" if fraction

      rounded = value.round(2)
      (rounded % 1).zero? ? rounded.to_i.to_s : rounded.to_s
    end
  end
end
