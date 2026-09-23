# A normalized wording (the recipe parser's key) that resolved to a food in
# this kitchen. The cache that makes a line cost the model once per kitchen,
# ever — and, when a user merges two foods, the rule that carries the merge
# forward to every future line.
class FoodAlias < ApplicationRecord
  belongs_to :kitchen
  belongs_to :food

  validates :key, presence: true, uniqueness: { scope: :kitchen_id }
end
