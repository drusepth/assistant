module Recipes
  # One ingredient line of typed text → one structured row
  # (D-recipe-primitive). Capture stays a paste: the user writes
  # "2 tbsp olive oil, plus more for drizzling" and the pantry match and
  # the grocery list get quantity/unit/item out of it, deterministically,
  # with no model call. The raw line is always kept, so a line this parser
  # reads badly still reads *right* on screen and can be fixed by hand.
  module Parse
    # Canonical unit => everything people write for it. Longest alias wins,
    # so "fl oz" beats "oz" and "tablespoons" beats "t".
    UNITS = {
      "g" => %w[ g gr gram grams ],
      "kg" => %w[ kg kilo kilos kilogram kilograms ],
      "mg" => %w[ mg milligram milligrams ],
      "oz" => %w[ oz ounce ounces ],
      "lb" => %w[ lb lbs pound pounds ],
      "ml" => %w[ ml milliliter milliliters millilitre millilitres cc ],
      "l" => %w[ l liter liters litre litres ],
      "fl oz" => [ "fl oz", "fl. oz.", "fl oz.", "fluid ounce", "fluid ounces" ],
      "tsp" => %w[ t tsp tsp. teaspoon teaspoons ],
      "tbsp" => %w[ tbs tbsp tbsp. tblsp tablespoon tablespoons ],
      "cup" => %w[ c cup cups ],
      "pint" => %w[ pt pint pints ],
      "quart" => %w[ qt quart quarts ],
      "gallon" => %w[ gal gallon gallons ],
      "clove" => %w[ clove cloves ],
      "can" => %w[ can cans tin tins ],
      "jar" => %w[ jar jars ],
      "package" => %w[ pkg package packages packet packets ],
      "bunch" => %w[ bunch bunches ],
      "sprig" => %w[ sprig sprigs ],
      "stick" => %w[ stick sticks ],
      "slice" => %w[ slice slices ],
      "piece" => %w[ piece pieces ],
      "head" => %w[ head heads ],
      "handful" => %w[ handful handfuls ],
      "pinch" => %w[ pinch pinches ],
      "dash" => %w[ dash dashes ]
    }.freeze

    UNIT_LOOKUP = UNITS.flat_map { |canonical, aliases| aliases.map { |a| [ a, canonical ] } }.to_h.freeze
    # `.source`, not the Regexp itself: interpolating a Regexp object embeds
    # it as (?-mix:…), which would override the /i and miss "Tbsp.".
    UNIT_PATTERN = /\A(#{Regexp.union(UNIT_LOOKUP.keys.sort_by { |a| -a.length }).source})\.?\s+/i

    # Adjectives that describe *this* pepper rather than name a different
    # ingredient, dropped from the match key only. Deliberately short:
    # "ground" stays (ground beef is not beef), "smoked" stays.
    DESCRIPTORS = %w[
      fresh freshly dried large small medium ripe good quality organic
      finely roughly coarsely thinly chopped diced sliced minced grated
      shredded crushed peeled cooked uncooked raw softened melted warm cold
      room-temperature boneless skinless extra plus
    ].freeze

    OPTIONAL_MARKERS = /\(\s*optional\s*\)|,\s*optional\b|\boptional:\s*/i
    BULLET = /\A\s*[-–—*•·]\s*/

    module_function

    # Text (one ingredient per line) → row attributes, in order. Blank
    # lines are skipped; a line that's only a heading ("For the sauce:")
    # is kept as an unquantified item so the cook still sees it.
    def lines(text)
      text.to_s.lines.map(&:strip).reject(&:blank?).each_with_index.map do |line, index|
        line_attributes(line).merge(position: index)
      end
    end

    def line_attributes(line)
      raw = line.strip
      rest = raw.sub(BULLET, "")

      optional = rest.match?(OPTIONAL_MARKERS)
      rest = rest.gsub(OPTIONAL_MARKERS, " ").squeeze(" ").strip

      quantity, rest = Quantity.parse(rest)
      unit, rest = split_unit(rest)
      rest = rest.sub(/\Aof\s+/i, "")
      item, note = split_note(rest)

      { quantity: quantity, unit: unit, item: item.presence || raw, note: note,
        raw: raw, optional: optional, item_key: key_for(item.presence || raw) }
    end

    # The pantry/grocery match key: lowercase, no parentheticals, no
    # descriptors, singular. "2 large Ripe Avocados (halved)" → "avocado".
    def key_for(item)
      words = item.to_s.downcase
        .gsub(/\([^)]*\)/, " ")
        .gsub(/[^a-z0-9\s-]/, " ")
        .split
        .reject { |word| DESCRIPTORS.include?(word) }

      return item.to_s.downcase.strip.squeeze(" ") if words.empty?

      words[..-2].join(" ").then { |head| [ head, words.last.singularize ] }.reject(&:blank?).join(" ")
    end

    def split_unit(text)
      match = text.match(UNIT_PATTERN)
      return [ nil, text ] if match.nil?

      [ UNIT_LOOKUP.fetch(match[1].downcase.delete_suffix(".")), match.post_match ]
    end

    # "onions, finely chopped" → ["onions", "finely chopped"]. Only the
    # first comma splits, and only when what follows reads as preparation
    # rather than part of the name.
    def split_note(text)
      head, _, tail = text.partition(",")
      [ head.strip, tail.strip.presence ]
    end
  end
end
