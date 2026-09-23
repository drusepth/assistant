class Section < ApplicationRecord
  belongs_to :parent, class_name: "Section", optional: true
  has_many :children, -> { order(:position) }, class_name: "Section",
    foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy
  has_many :section_taggings, dependent: :destroy
  has_many :user_sections, dependent: :destroy
  has_many :access_grants, as: :subject, dependent: :destroy
  # Both of these are *about* a hobby lens rather than tagged with it, so
  # they end where it ends: what the hobby means to the reader
  # (D-story-matching §4) and the stories the model filed under it. Removing
  # a hobby raised a foreign-key error until they said so.
  has_many :hobby_briefs, dependent: :destroy
  has_many :story_routings, dependent: :destroy

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true

  # Models that own a lens each (D-pet-primitive): a Pet holds a custom child
  # of People. The row says which in `owner_type` (D-owned-lens), set when
  # the owner creates it, so "is this Rex's lens or a group?" is a column
  # read rather than a question every surface has to remember to ask.
  LENS_OWNERS = %w[ Pet ].freeze

  validates :owner_type, inclusion: { in: LENS_OWNERS }, allow_nil: true

  scope :top_level, -> { where(parent_id: nil).order(:position) }
  # User-created lenses (D25: hobby sub-lenses) — the only sections that can
  # be removed; the seeded taxonomy cannot.
  scope :custom, -> { where(custom: true) }
  scope :owned, -> { where.not(owner_type: nil) }
  scope :unowned, -> { where(owner_type: nil) }

  def top_level? = parent_id.nil?

  def owned? = owner_type.present?

  # A lens the user made can be removed; one a record owns cannot — Rex's
  # lens is Rex's, and removing the pet is what removes it.
  def removable? = custom? && !owned?

  # People's groups (D-people-circles): its children, less the lenses a
  # record owns. A pet's lens is a child of People too (D-pet-primitive) so
  # "about Rex" is an ordinary tag, but Rex is not a group of people — every
  # surface that offers "add to a group" or filters by one reads this.
  def self.people_groups
    find_by(slug: "people")&.children&.unowned || none
  end

  # What a section's own row of sub-areas lists (Settings, onboarding):
  # the ones that are areas of it. A pet is not an area of People.
  def subsections = children.unowned

  # "Budget" reads ambiguously outside its section; "Money · Budget" doesn't.
  # An owned lens is qualified by what owns it instead: Rex is not a kind of
  # People, and "People · Dimitri" read as a person named Dimitri.
  def qualified_name
    return "#{owner_type.underscore.humanize} · #{name}" if owned?

    parent ? "#{parent.name} · #{name}" : name
  end
end
