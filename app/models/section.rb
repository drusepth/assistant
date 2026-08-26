class Section < ApplicationRecord
  belongs_to :parent, class_name: "Section", optional: true
  has_many :children, -> { order(:position) }, class_name: "Section",
    foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy
  has_many :section_taggings, dependent: :destroy
  has_many :user_sections, dependent: :destroy
  has_many :access_grants, as: :subject, dependent: :destroy

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true

  # Models that own a lens each (D-pet-primitive): a Pet holds a custom child
  # of People. One registry, two consumers — Sections::Panel resolves the
  # lens's page through it, and `removable?` keeps the generic "remove this
  # group" button off a lens whose life belongs to a record.
  LENS_OWNERS = %w[ Pet ].freeze

  scope :top_level, -> { where(parent_id: nil).order(:position) }
  # User-created lenses (D25: hobby sub-lenses) — the only sections that can
  # be removed; the seeded taxonomy cannot.
  scope :custom, -> { where(custom: true) }

  def top_level? = parent_id.nil?

  # The model name owning this lens, if any. Costs nothing for the seeded
  # taxonomy — every owner is a user-created lens.
  def lens_owner
    return nil unless custom?

    LENS_OWNERS.find { |model| model.constantize.exists?(section_id: id) }
  end

  # A lens the user made can be removed; one a record owns cannot — Rex's
  # lens is Rex's, and removing the pet is what removes it.
  def removable? = custom? && lens_owner.nil?

  # Every owned lens in the instance, in one query per owner model: what a
  # grid of user-made lenses has to leave out, since those cards belong to
  # the records that own them.
  def self.owned_lens_ids
    LENS_OWNERS.flat_map { |model| model.constantize.distinct.pluck(:section_id) }
  end

  # "Budget" reads ambiguously outside its section; "Money · Budget" doesn't.
  def qualified_name
    parent ? "#{parent.name} · #{name}" : name
  end
end
