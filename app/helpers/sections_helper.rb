# Stable identity colors per top-level section; subsections inherit their
# parent's color. Literal class strings so Tailwind's scanner sees them.
module SectionsHelper
  CHIP_CLASSES = {
    "health" => "bg-rose-100 text-rose-800",
    "hobbies" => "bg-amber-100 text-amber-800",
    "education" => "bg-violet-100 text-violet-800",
    "career" => "bg-sky-100 text-sky-800",
    "people" => "bg-emerald-100 text-emerald-800",
    "money" => "bg-lime-100 text-lime-800",
    "rights" => "bg-orange-100 text-orange-800"
  }.freeze

  DOT_CLASSES = {
    "health" => "bg-rose-500",
    "hobbies" => "bg-amber-500",
    "education" => "bg-violet-500",
    "career" => "bg-sky-500",
    "people" => "bg-emerald-500",
    "money" => "bg-lime-600",
    "rights" => "bg-orange-500"
  }.freeze

  def section_chip_classes(section)
    CHIP_CLASSES.fetch(section_root_slug(section), "bg-stone-100 text-stone-700")
  end

  def section_dot_classes(section)
    DOT_CLASSES.fetch(section_root_slug(section), "bg-stone-400")
  end

  def section_root_slug(section)
    (section.parent || section).slug
  end

  # Chip suggestions for the hobby capture card — a broad, cheap-to-start
  # spread, minus the lenses the household already has.
  HOBBY_SUGGESTIONS = [
    "Reading", "Cooking", "Baking", "Gardening", "Drawing", "Photography",
    "Gaming", "Board games", "Hiking", "Running", "Guitar", "Knitting",
    "Woodworking", "Writing"
  ].freeze

  def hobby_suggestions(hobbies_section)
    taken = hobbies_section.children.map { |child| child.name.downcase }
    HOBBY_SUGGESTIONS.reject { |name| taken.include?(name.downcase) }
  end
end
