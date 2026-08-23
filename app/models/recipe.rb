# The eighth primitive (D-recipe-primitive): a thing you cook, owned by one
# user, multi-tagged like everything else (the low-sodium ones are Health,
# Grandma's are People). Ingredients are rows because the pantry match, the
# grocery list, and scaling all key off their quantities; the method is
# prose because nothing joins to step 4.
class Recipe < ApplicationRecord
  include Visible
  include Sectionable

  has_many :recipe_ingredients, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :recipe
  # What the pantry match, the grocery list, and "how many ingredients is
  # this" all mean by "ingredients": the dividers are presentation.
  has_many :shoppable_ingredients, -> { shoppable.order(:position, :id) },
    class_name: "RecipeIngredient", inverse_of: :recipe, dependent: nil
  has_many :recipe_book_entries, dependent: :destroy
  has_many :recipe_books, through: :recipe_book_entries
  has_many :share_links, as: :subject, dependent: :destroy

  has_one_attached :image do |attachable|
    attachable.variant :card, resize_to_fill: [ 600, 450 ], format: :webp,
      saver: { quality: 80, strip: true }
    attachable.variant :hero, resize_to_limit: [ 1600, 1600 ], format: :webp,
      saver: { quality: 85, strip: true }
  end

  # nil import_status = typed by hand, which is most recipes. The rest
  # follow the photo/document ingestion states so a stuck or failed import
  # is visible rather than silent.
  enum :import_status, {
    queued: "queued", processing: "processing", imported: "imported", failed: "failed"
  }, prefix: :import

  validates :title, presence: true
  validates :servings, :prep_minutes, :cook_minutes,
    numericality: { only_integer: true, greater_than: 0, less_than: 100_000 }, allow_nil: true
  # The source link is rendered as an href, and a recipe travels (household
  # grants, share links, another instance's import) — so a `javascript:` URL
  # typed into the edit form would be stored XSS against whoever opens it.
  # The import paths each vetted the scheme already; the model is where every
  # path meets, so it belongs here.
  validates :source_url, format: { with: %r{\Ahttps?://\S+\z},
    message: "needs to start with http:// or https://" }, allow_blank: true
  validate :image_must_be_an_image

  scope :favorites, -> { where(favorite: true) }

  # What a cook actually asks a box of recipes: what's new, what do we
  # really eat, what have I saved and never made, what's quick tonight.
  SORTS = {
    "title" => "A to Z",
    "recent" => "Recently added",
    "cooked" => "Cooked most recently",
    "never" => "Never cooked",
    "quick" => "Quickest first"
  }.freeze

  scope :sorted_by, ->(key) {
    case key
    when "recent" then order(created_at: :desc)
    # Nulls last by hand: SQLite's NULLS LAST support is newer than the
    # oldest SQLite an owner might be self-hosting on.
    when "cooked" then order(Arel.sql("last_cooked_on IS NULL, last_cooked_on DESC"))
    when "never" then where(times_cooked: 0).order(created_at: :asc)
    when "quick" then order(Arel.sql(
      "COALESCE(prep_minutes, 0) + COALESCE(cook_minutes, 0) = 0, " \
      "COALESCE(prep_minutes, 0) + COALESCE(cook_minutes, 0) ASC"))
    else order(Arel.sql("LOWER(recipes.title)"))
    end
  }

  # Title, blurb, or any ingredient — one LIKE, no index ceremony until it
  # hurts.
  scope :search, ->(term) {
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term.to_s.strip)}%"
    where("recipes.title LIKE :q OR recipes.description LIKE :q", q: pattern)
      .or(where(id: RecipeIngredient.where("item LIKE :q", q: pattern).select(:recipe_id)))
  }

  # The book sharing path (D-recipe-primitive), the album clause again: a
  # grant on a book exposes the recipes in it — but only those the grant's
  # grantor owns, so a future collaborative book (Q-recipe-collab) can't
  # leak a contributor's recipe through someone else's grant.
  def self.extra_visibility_clauses
    [ <<~SQL ]
      EXISTS (
        SELECT 1 FROM access_grants
        INNER JOIN recipe_book_entries
          ON recipe_book_entries.recipe_book_id = access_grants.subject_id
          AND recipe_book_entries.recipe_id = recipes.id
        WHERE access_grants.grantee_id = :viewer_id
          AND access_grants.subject_type = 'RecipeBook'
          AND access_grants.grantor_id = recipes.user_id
      )
    SQL
  end

  # Capture stays a paste: assigning the textarea replaces the rows, and
  # reading it hands back exactly what was typed (rows keep their raw line).
  def ingredients_text
    @ingredients_text ||= recipe_ingredients.map(&:raw).join("\n")
  end

  def ingredients_text=(text)
    @ingredients_text = text.to_s
    @ingredients_text_changed = true
  end

  after_save :rebuild_ingredients

  def total_minutes
    [ prep_minutes, cook_minutes ].compact.sum.presence&.nonzero?
  end

  def timing
    parts = []
    parts << "#{prep_minutes} min prep" if prep_minutes
    parts << "#{cook_minutes} min cook" if cook_minutes
    parts.join(" · ")
  end

  # Numbered steps out of prose: blank-line-separated blocks, or one step
  # per line when the writer didn't leave blank lines. Existing numbering
  # ("1. ") is stripped so it isn't rendered twice.
  def steps
    body = directions.to_s.strip
    return [] if body.empty?

    blocks = body.include?("\n\n") ? body.split(/\n{2,}/) : body.split("\n")
    blocks.map { |step| step.strip.sub(/\A\d+[.)]\s*/, "") }.reject(&:blank?)
  end

  # Scaling is multiplication and nothing else (Q-recipe-scale-units): a
  # line the parser couldn't quantify comes back untouched rather than
  # invented.
  def scale_factor(for_servings)
    return 1.0 if servings.blank? || servings.zero? || for_servings.blank?

    factor = for_servings.to_f / servings
    factor.positive? ? factor : 1.0
  end

  # Import needs a configured model to do its best work, but not to work:
  # with none, ImportRecipeJob falls back to the deterministic splitter.
  def importable_profile
    profile = user.household.model_profile
    profile if profile&.configured?
  end

  def importing? = import_queued? || import_processing?

  def enqueue_import!
    update!(import_status: :queued, import_error: nil)
    ImportRecipeJob.perform_later(self)
  end

  def cooked!(on = Date.current)
    update!(last_cooked_on: on, times_cooked: times_cooked + 1)
  end

  private
    def rebuild_ingredients
      return unless @ingredients_text_changed

      @ingredients_text_changed = false
      recipe_ingredients.destroy_all
      Recipes::Parse.lines(@ingredients_text).each do |attributes|
        recipe_ingredients.create!(attributes)
      end
      recipe_ingredients.reset
    end

    def image_must_be_an_image
      return unless image.attached?

      unless image.blob.content_type.to_s.start_with?("image/")
        errors.add(:image, "must be an image")
      end
    end
end
