class SectionTagging < ApplicationRecord
  belongs_to :section
  belongs_to :taggable, polymorphic: true

  validates :section_id, uniqueness: { scope: [ :taggable_type, :taggable_id ] }
end
