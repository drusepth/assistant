class Section < ApplicationRecord
  belongs_to :parent, class_name: "Section", optional: true
  has_many :children, -> { order(:position) }, class_name: "Section",
    foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy
  has_many :section_taggings, dependent: :destroy
  has_many :user_sections, dependent: :destroy
  has_many :access_grants, as: :subject, dependent: :destroy

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true

  scope :top_level, -> { where(parent_id: nil).order(:position) }
  # User-created lenses (D21: hobby sub-lenses) — the only sections that can
  # be removed; the seeded taxonomy cannot.
  scope :custom, -> { where(custom: true) }

  def top_level? = parent_id.nil?

  # "Budget" reads ambiguously outside its section; "Money · Budget" doesn't.
  def qualified_name
    parent ? "#{parent.name} · #{name}" : name
  end
end
