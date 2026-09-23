# Something in the kitchen (D-kitchen; docs/FOOD_PLAN.md §3): a row of the
# kitchen, like a list line, so anyone who cooks here can add it, move it to
# the freezer, or mark it used up. Whether it's here is the signal; how much
# is prose (Q-pantry-quantities).
class PantryItem < ApplicationRecord
  # Two days' warning is enough to plan a dinner around it and short enough
  # that the warning still means something.
  EXPIRING_WITHIN = 2

  belongs_to :kitchen
  belongs_to :food, optional: true
  belongs_to :added_by, class_name: "User", optional: true
  belongs_to :shopping_list_item, optional: true

  validates :item, :item_key, presence: true, length: { maximum: 200 }
  validates :quantity_note, length: { maximum: 100 }
  validates :location, inclusion: { in: Food::LOCATIONS.keys }

  scope :in_location, ->(location) { where(location: location) }
  # Soonest-expiring first, then the ones with no date, by name.
  scope :by_expiry, -> { order(Arel.sql("expires_on IS NULL, expires_on ASC, item ASC")) }
  scope :expiring, ->(within: EXPIRING_WITHIN, today: Date.current) { where(expires_on: ..(today + within)) }

  def location_label = Food::LOCATIONS.fetch(location)

  def expired?(today = Date.current) = expires_on.present? && expires_on < today
  def expiring?(today = Date.current) = expires_on.present? && expires_on <= today + EXPIRING_WITHIN

  # Freezing stops the clock the fridge was running — the date that was
  # true in the fridge isn't true in the freezer, and a guessed new one is
  # the kind of number this app doesn't invent.
  def move_to!(location)
    update!(location: location, expires_on: (location == "freezer" ? nil : expires_on))
  end
end
