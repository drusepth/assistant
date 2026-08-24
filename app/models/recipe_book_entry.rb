class RecipeBookEntry < ApplicationRecord
  belongs_to :recipe_book
  belongs_to :recipe

  validates :recipe_id, uniqueness: { scope: :recipe_book_id }
end
