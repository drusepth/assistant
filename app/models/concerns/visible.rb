# Private-by-default visibility (D9). An item can be seen by:
#   1. its owner,
#   2. a user holding an item-level AccessGrant for it,
#   3. a user holding a Section-level AccessGrant from the item's owner
#      for a section the item is tagged with.
# visible_to is the single read path for authorization — controllers and
# cross-user AI features must never query primitives any other way.
module Visible
  extend ActiveSupport::Concern

  included do
    belongs_to :user

    has_many :access_grants, as: :subject, dependent: :destroy

    scope :visible_to, ->(viewer) {
      where(<<~SQL.squish, viewer_id: viewer.id, type: name)
        #{table_name}.user_id = :viewer_id
        OR EXISTS (
          SELECT 1 FROM access_grants
          WHERE access_grants.grantee_id = :viewer_id
            AND access_grants.subject_type = :type
            AND access_grants.subject_id = #{table_name}.id
        )
        OR EXISTS (
          SELECT 1 FROM access_grants
          INNER JOIN section_taggings
            ON section_taggings.section_id = access_grants.subject_id
            AND section_taggings.taggable_type = :type
            AND section_taggings.taggable_id = #{table_name}.id
          WHERE access_grants.grantee_id = :viewer_id
            AND access_grants.subject_type = 'Section'
            AND access_grants.grantor_id = #{table_name}.user_id
        )
      SQL
    }
  end

  def visible_to?(viewer)
    self.class.visible_to(viewer).exists?(id: id)
  end
end
