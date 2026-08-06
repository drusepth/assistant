# Multi-tagging by section (the "lens" half of lens-over-primitives, D5).
# Sections never own tables; every cross-section view is a query over
# primitives, every section page is an in_section query.
module Sectionable
  extend ActiveSupport::Concern

  included do
    has_many :section_taggings, as: :taggable, dependent: :destroy
    has_many :sections, through: :section_taggings

    scope :in_section, ->(section) {
      where(id: SectionTagging.where(section_id: section, taggable_type: name).select(:taggable_id))
    }
  end
end
