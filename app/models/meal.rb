# One planned meal (D-kitchen; docs/FOOD_PLAN.md §2): a date, a slot, and a
# recipe or a line of text — "leftovers", "takeout", "at Mum's". A row of
# the kitchen, so the plan is the household's to rearrange, and the
# Calendar draws it as a band for everyone who cooks here.
class Meal < ApplicationRecord
  SLOTS = {
    "breakfast" => "Breakfast", "lunch" => "Lunch", "dinner" => "Dinner", "snack" => "Snack"
  }.freeze

  belongs_to :kitchen
  belongs_to :recipe, optional: true
  belongs_to :cook, class_name: "User", optional: true
  belongs_to :event, optional: true

  validates :date, presence: true
  validates :slot, inclusion: { in: SLOTS.keys }
  validates :title, presence: true, length: { maximum: 120 }
  validates :servings, numericality: { only_integer: true, in: 1..100 }, allow_nil: true

  before_validation :title_from_recipe
  # Written straight to the column: the in-memory value may be stale (the
  # week's list stamps it with update_columns), and a stale nil wouldn't
  # count as a change.
  after_update :forget_listing, if: -> { saved_change_to_recipe_id? || saved_change_to_servings? }

  scope :in_order, -> { order(:date, Arel.sql(slot_order_sql), :id) }
  scope :between, ->(range) { where(date: range) }

  def self.slot_order_sql
    "CASE slot #{SLOTS.keys.each_with_index.map { |slot, index| "WHEN '#{slot}' THEN #{index}" }.join(" ")} ELSE 9 END"
  end

  def slot_label = SLOTS.fetch(slot)

  # The recipe, only for someone allowed to open it. Everyone reads the
  # title; not everyone can see the dish.
  def recipe_for(viewer)
    recipe if recipe&.visible_to?(viewer)
  end

  private
    def title_from_recipe
      self.title = recipe.title if recipe && (title.blank? || will_save_change_to_recipe_id?)
    end

    def forget_listing
      update_column(:listed_at, nil)
    end
end
