# One food in a kitchen's catalog (D-food-catalog; docs/FOOD_PLAN.md §2).
# Recipe ingredients, list lines and pantry items are matched on this row,
# never on their wording: the model files each new line onto a food once,
# its answer validated into the closed sets below and the rows that exist.
# The user's edits — a merge, a moved aisle — are their own rules.
class Food < ApplicationRecord
  AISLES = {
    "produce" => "Fruit & veg",
    "bakery" => "Bakery",
    "meat" => "Meat & fish",
    "dairy" => "Dairy & eggs",
    "frozen" => "Frozen",
    "dry_goods" => "Pasta, rice & grains",
    "canned" => "Tins & jars",
    "baking" => "Baking & spices",
    "condiments" => "Sauces & oils",
    "snacks" => "Snacks",
    "breakfast" => "Breakfast",
    "drinks" => "Drinks",
    "household" => "Household",
    "personal_care" => "Personal care",
    "pet" => "Pet",
    "other" => "Other"
  }.freeze

  # The nine major allergens US labelling law names. Allergens only ever
  # *exclude* — the app never calls a dish safe — and every mention carries
  # "check the packet", because a model-filed allergen is a prompt to look,
  # not a label.
  ALLERGENS = {
    "milk" => "Milk", "eggs" => "Eggs", "fish" => "Fish", "shellfish" => "Shellfish",
    "tree_nuts" => "Tree nuts", "peanuts" => "Peanuts", "wheat" => "Wheat",
    "soy" => "Soy", "sesame" => "Sesame"
  }.freeze

  LOCATIONS = {
    "fridge" => "Fridge", "freezer" => "Freezer", "pantry" => "Cupboard"
  }.freeze

  belongs_to :kitchen
  belongs_to :kind_of, class_name: "Food", optional: true
  has_many :aliases, class_name: "FoodAlias", dependent: :delete_all
  has_many :kinds, class_name: "Food", foreign_key: :kind_of_id, inverse_of: :kind_of, dependent: :nullify
  has_many :shopping_list_items, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }
  validates :aisle, inclusion: { in: AISLES.keys }, allow_nil: true
  validates :default_location, inclusion: { in: LOCATIONS.keys }, allow_nil: true
  validate :allergens_are_known
  validate :kind_of_is_one_level_in_this_kitchen

  normalizes :allergens, with: ->(list) { Array(list).map(&:to_s).compact_blank.uniq & ALLERGENS.keys }
  normalizes :aisle, :default_location, with: ->(value) { value.presence }

  def aisle_label = AISLES[aisle]
  def location_label = LOCATIONS[default_location]
  def allergen_labels = allergens.map { |allergen| ALLERGENS.fetch(allergen) }

  # "These are the same": everything that pointed here points there, the
  # wording that reached this food reaches that one from now on, and this
  # row goes. A user rule — the model never merges.
  def merge_into!(target)
    raise ArgumentError, "can't merge a food into itself" if target == self
    raise ArgumentError, "foods must share a kitchen" if target.kitchen_id != kitchen_id

    transaction do
      aliases.update_all(food_id: target.id)
      shopping_list_items.update_all(food_id: target.id)
      Food.where(kind_of_id: id).where.not(id: target.id).update_all(kind_of_id: target.id)
      target.update!(kind_of: nil) if target.kind_of_id == id
      yield target if block_given?
      target.update!(allergens: target.allergens | allergens)
      destroy!
    end
  end

  private
    def allergens_are_known
      errors.add(:allergens, "must be from the list") unless (allergens - ALLERGENS.keys).empty?
    end

    def kind_of_is_one_level_in_this_kitchen
      return if kind_of.nil?

      errors.add(:kind_of, "must be in the same kitchen") if kind_of.kitchen_id != kitchen_id
      errors.add(:kind_of, "can't be itself") if kind_of_id == id
      errors.add(:kind_of, "must be a general food, not itself a kind of something") if kind_of.kind_of_id.present?
    end
end
