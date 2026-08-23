# A user-curated set of their own recipes (D-recipe-primitive) — a spring
# book, a soup book, Grandma's book. Like an album, it is deliberate
# curation rather than a section lens, one recipe lives in many books, and
# a grant on the book carries its recipes with it.
class RecipeBook < ApplicationRecord
  include Visible

  has_many :recipe_book_entries, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :recipe_book
  has_many :recipes, through: :recipe_book_entries
  has_many :share_links, as: :subject, dependent: :destroy
  belongs_to :cover_recipe, class_name: "Recipe", optional: true

  validates :title, presence: true
  validate :cover_recipe_is_own

  # An explicit cover wins; otherwise the newest recipe that has a picture,
  # so a book isn't represented by a blank tile while a photogenic one sits
  # inside it.
  def cover
    return cover_recipe if cover_recipe

    recipes.with_attached_image.order(created_at: :desc)
      .find { |recipe| recipe.image.attached? } || recipes.order(created_at: :desc).first
  end

  private
    def cover_recipe_is_own
      return if cover_recipe.nil?

      errors.add(:cover_recipe, "must be one of your recipes") if cover_recipe.user_id != user_id
    end
end
