class Section < ApplicationRecord
  belongs_to :parent, class_name: "Section", optional: true
  has_many :children, -> { order(:position) }, class_name: "Section",
    foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy
  has_many :section_taggings, dependent: :destroy

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true

  scope :top_level, -> { where(parent_id: nil).order(:position) }

  def top_level? = parent_id.nil?
end
