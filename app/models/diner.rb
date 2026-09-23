# Someone who eats from this kitchen (D-food-suggestions): a household member
# or anyone else — "Grandma, Sundays". Their allergens exclude dishes by
# join; their diet note is prose for the model to honour, and is never
# parsed. Nothing here is inferred from anybody's health records.
class Diner < ApplicationRecord
  belongs_to :kitchen
  belongs_to :user, optional: true

  validates :name, presence: true, length: { maximum: 60 }
  validates :diet_note, length: { maximum: 200 }
  normalizes :allergens, with: ->(list) { Array(list).map(&:to_s).compact_blank.uniq & Food::ALLERGENS.keys }

  def allergen_labels = allergens.map { |allergen| Food::ALLERGENS.fetch(allergen) }
end
