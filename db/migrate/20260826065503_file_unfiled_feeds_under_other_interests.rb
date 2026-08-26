class FileUnfiledFeedsUnderOtherInterests < ActiveRecord::Migration[8.1]
  # The invariant D-hobby-feeds rests on: every feed has a hobby, or has
  # Other Interests. Feeds followed before the classifier existed carry
  # whatever lens the user picked in the form, which for most rows is
  # nothing — so this files those, and creates the catch-all lens only if
  # there is something to put in it (it is created on demand, not seeded).
  #
  # Raw SQL rather than the models: a migration that goes through
  # Hobbies::OtherInterests would break the day that class changes.
  def up
    unfiled = select_values(<<~SQL.squish)
      SELECT feeds.id FROM feeds
      WHERE NOT EXISTS (
        SELECT 1 FROM section_taggings
        WHERE section_taggings.taggable_type = 'Feed' AND section_taggings.taggable_id = feeds.id
      )
    SQL
    return if unfiled.empty?

    now = Time.current.utc.iso8601
    hobbies_id = select_value("SELECT id FROM sections WHERE slug = 'hobbies'")
    return unless hobbies_id

    lens_id = select_value("SELECT id FROM sections WHERE slug = 'other-interests'")
    lens_id ||= begin
      position = select_value("SELECT COALESCE(MAX(position), 0) + 1 FROM sections WHERE parent_id = #{hobbies_id}")
      execute <<~SQL.squish
        INSERT INTO sections (slug, name, parent_id, position, custom, created_at, updated_at)
        VALUES ('other-interests', 'Other Interests', #{hobbies_id}, #{position}, 0, '#{now}', '#{now}')
      SQL
      select_value("SELECT id FROM sections WHERE slug = 'other-interests'")
    end

    unfiled.each do |feed_id|
      execute <<~SQL.squish
        INSERT INTO section_taggings (section_id, taggable_type, taggable_id, created_at, updated_at)
        VALUES (#{lens_id}, 'Feed', #{feed_id}, '#{now}', '#{now}')
      SQL
    end
  end

  def down
    # The lens goes, its taggings go with it, and the feeds are unfiled
    # again — which is exactly the state this migration found them in.
    execute <<~SQL.squish
      DELETE FROM section_taggings
      WHERE taggable_type = 'Feed'
        AND section_id IN (SELECT id FROM sections WHERE slug = 'other-interests')
    SQL
    execute "DELETE FROM sections WHERE slug = 'other-interests'"
  end
end
