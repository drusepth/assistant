# One of a kitchen's shopping lists (D-kitchen; docs/FOOD_PLAN.md §3). Its
# lines are rows of the list — no owner, no grant of their own — so anyone
# who can cook in the kitchen can add to it and check things off.
class ShoppingList < ApplicationRecord
  DEFAULT_NAME = "Groceries".freeze

  # Checked lines stay listed "in the basket" for the rest of the day they
  # were checked, then leave the list; they're kept this long for "what did
  # we buy last time" before the sweep deletes them.
  HISTORY = 30.days

  belongs_to :kitchen
  has_many :items, -> { order(:created_at, :id) }, class_name: "ShoppingListItem",
    dependent: :delete_all, inverse_of: :shopping_list

  validates :name, presence: true, length: { maximum: 60 }

  scope :ordered, -> { order(:position, :id) }

  # The list the hub shows first, made on first use.
  def self.default_for(kitchen)
    kitchen.shopping_lists.ordered.first || kitchen.shopping_lists.create!(name: DEFAULT_NAME)
  end

  def open_items = items.open
  def basket_items = items.checked_since(Time.current.beginning_of_day)

  # Lines typed or pasted in, one per line → rows, merged into what's
  # already on the list (ShoppingLists::Add). Returns the rows touched.
  def add_lines(text, by:, recipe: nil)
    ShoppingLists::Add.new(self, by: by).lines(text, recipe: recipe)
  end

  # Old checked lines leave for good. A sweep, not a per-request cost.
  def self.sweep_history(now: Time.current)
    ShoppingListItem.where(checked_at: ...(now - HISTORY)).delete_all
  end
end
