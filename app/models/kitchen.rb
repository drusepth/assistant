# The household's kitchen (D-kitchen; docs/FOOD_PLAN.md). One container whose
# shopping lists, fridge and meal plan are its rows — none of them owned by
# anyone but the kitchen — so one grant shares the lot. And it is the first
# grant in the app that writes: whoever can see a kitchen can cook in it
# (add to and check off the lists, change the fridge, fill in the plan).
# Renaming, deleting and re-sharing stay with the owner.
class Kitchen < ApplicationRecord
  include Visible

  DEFAULT_NAME = "Home".freeze

  has_many :shopping_lists, dependent: :destroy
  has_many :food_aliases, dependent: :delete_all
  has_many :foods, dependent: :destroy
  has_many :pantry_items, dependent: :delete_all
  has_many :meals, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 60 }
  validate :aisle_order_is_aisles

  # Anyone who can see a kitchen can cook in it. Kept as its own predicate so
  # the controllers say what they mean, and so a read-only share has one
  # place to arrive if it is ever wanted.
  def cookable_by?(user) = visible_to?(user)

  def owned_by?(user) = user_id == user.id

  # Everyone who can cook here: the owner and whoever they shared it with.
  def cooks = User.where(id: access_grants.select(:grantee_id)).or(User.where(id: user_id))

  # The share-this-kitchen card: shown to the owner until they answer, and
  # only when there is somebody to share with.
  def share_prompt_pending? = share_prompt_answered_at.nil?

  # The aisles in the order this household walks their store, then any the
  # owner hasn't placed, in the catalog's order.
  def aisles_in_order
    (aisle_order & Food::AISLES.keys) + (Food::AISLES.keys - aisle_order)
  end

  # Every kitchen page subscribes to this, so the item a partner adds at home
  # appears on the phone in the store (Turbo morphs the page in place).
  def broadcast_change
    touch
    Turbo::StreamsChannel.broadcast_refresh_later_to(self)
  end

  private
    def aisle_order_is_aisles
      errors.add(:aisle_order, "must be aisles") unless (Array(aisle_order) - Food::AISLES.keys).empty?
    end
end
