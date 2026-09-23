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

  has_many :put_away_items, class_name: "PantryItem", dependent: :nullify

  # Checking a line off puts it in the kitchen (docs/FOOD_PLAN.md §3) —
  # unless the household keeps no fridge list.
  def check!(by:)
    transaction do
      update!(checked_at: Time.current, checked_by: by)
      kitchen = shopping_list.kitchen
      Kitchens::Pantry.new(kitchen, by: by).put_away(self) if kitchen.put_away_on_check?
    end
  end

  # The undo: un-checking takes back out what checking put away — only the
  # row it made, never one that was already in the fridge.
  def uncheck!
    transaction do
      update!(checked_at: nil, checked_by: nil)
      put_away_items.destroy_all
    end
  end

  # "2 tins chickpeas" — the recipe ingredient's own formatting, so a list
  # line reads exactly like the recipe it came from.
  def display
    [ Recipes::Quantity.with_unit(quantity, unit), item ].compact_blank.join(" ")
  end

  def amount = Recipes::Quantity.with_unit(quantity, unit)
end
