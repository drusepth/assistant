# Private-by-default visibility (D9). An item can be seen by:
#   1. its owner,
#   2. a user holding an item-level AccessGrant for it,
#   3. a user holding a Section-level AccessGrant from the item's owner
#      for a section the item is tagged with,
#   4. any OR-branch the including model adds via extra_visibility_clauses
#      (D-photos-primitive: Photo adds album-grant visibility this way).
# visible_to is the single read path for authorization — controllers and
# cross-user AI features must never query primitives any other way.
module Visible
  extend ActiveSupport::Concern

  included do
    belongs_to :user

    has_many :access_grants, as: :subject, dependent: :destroy

    scope :visible_to, ->(viewer) {
      where(visibility_sql, viewer_id: viewer.id, type: name)
    }
  end

  class_methods do
    # Extra OR-branches for models with sharing paths beyond items and
    # sections. Clauses may reference the :viewer_id and :type binds.
    def extra_visibility_clauses = []

    def visibility_sql
      base = [
        "#{table_name}.user_id = :viewer_id",
        <<~SQL,
          EXISTS (
            SELECT 1 FROM access_grants
            WHERE access_grants.grantee_id = :viewer_id
              AND access_grants.subject_type = :type
              AND access_grants.subject_id = #{table_name}.id
          )
        SQL
        <<~SQL
          EXISTS (
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
      ]
      (base + extra_visibility_clauses).map(&:squish).join(" OR ")
    end
  end

  def visible_to?(viewer)
    self.class.visible_to(viewer).exists?(id: id)
  end
end
