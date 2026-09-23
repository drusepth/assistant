# One line of a shopping list. Parsed like a recipe ingredient, so a line
# added by hand and one added from a recipe merge on the same key.
class ShoppingListItem < ApplicationRecord
  belongs_to :shopping_list, touch: true
  belongs_to :recipe, optional: true
  belongs_to :food, optional: true
  belongs_to :added_by, class_name: "User", optional: true
  belongs_to :checked_by, class_name: "User", optional: true

  validates :item, :item_key, presence: true, length: { maximum: 200 }
  validates :note, length: { maximum: 200 }

  scope :open, -> { where(checked_at: nil) }
  scope :checked_since, ->(time) { where(checked_at: time..).order(checked_at: :desc) }

  def checked? = checked_at.present?

  def check!(by:) = update!(checked_at: Time.current, checked_by: by)

  def uncheck! = update!(checked_at: nil, checked_by: nil)

  # "2 tins chickpeas" — the recipe ingredient's own formatting, so a list
  # line reads exactly like the recipe it came from.
  def display
    [ Recipes::Quantity.format(quantity), unit_for_display, item ].compact_blank.join(" ")
  end

  private
    def unit_for_display
      return unit if unit.blank? || quantity.nil? || quantity <= 1 || !RecipeIngredient::COUNTABLE_UNITS.include?(unit)

      unit.pluralize
    end
end
