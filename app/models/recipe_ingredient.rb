# One parsed ingredient line (D-recipe-primitive). `raw` is the line as the
# user typed it and is what the edit form shows back; the parsed columns are
# what the pantry match, the grocery list, and scaling read.
class RecipeIngredient < ApplicationRecord
  belongs_to :recipe

  validates :item, :item_key, :raw, presence: true

  # Units that are words rather than abbreviations pluralize with the
  # number in front of them; "3 gs of flour" is not a thing anyone writes.
  COUNTABLE_UNITS = %w[
    cup clove can jar package bunch sprig stick slice piece head handful
    pinch dash pint quart gallon
  ].freeze

  def display(factor = 1.0)
    scaled = quantity * factor if quantity
    [ Recipes::Quantity.format(scaled), unit_for(scaled), item ].compact_blank.join(" ")
  end

  def unit_for(amount)
    return unit if unit.blank? || amount.nil? || amount <= 1 || !COUNTABLE_UNITS.include?(unit)

    unit.pluralize
  end

  def scaled?(factor) = quantity.present? && factor != 1.0
end
