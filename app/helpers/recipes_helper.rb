module RecipesHelper
  # A recipe with no photo shouldn't read as a broken one. Instead of a grey
  # icon, an untinted card gets a warm monogram tile drawn from the two
  # Organic ramps — stable per recipe (the same soup is the same colour
  # every time) and never a stock hue.
  TILE_TINTS = [
    "bg-primary-100 text-primary-800",
    "bg-sage-100 text-sage-800",
    "bg-primary-200 text-primary-900",
    "bg-sage-200 text-sage-900",
    "bg-stone-200 text-stone-700"
  ].freeze

  def recipe_tile_classes(recipe)
    TILE_TINTS[Zlib.crc32(recipe.title.to_s.downcase) % TILE_TINTS.size]
  end

  # First letters of the first two words: "Mum's lentil soup" → "ML".
  # Split on whitespace, not on word characters — otherwise the apostrophe
  # makes "Mum" and "s" two words and the soup reads "MS".
  def recipe_monogram(recipe)
    letters = recipe.title.to_s.split(/\s+/).filter_map { |word| word[/[[:alnum:]]/] }
    letters.first(2).join.upcase.presence || "?"
  end
end
