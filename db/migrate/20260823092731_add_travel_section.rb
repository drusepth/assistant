class AddTravelSection < ActiveRecord::Migration[8.1]
  # Travel is the eighth top-level section (D-travel-facet). db/seeds.rb
  # carries it for fresh installs; this migration is how the boxes that are
  # already running get it, since nobody re-runs seeds on an upgrade.
  #
  # Sections are enabled unless a user_sections row says otherwise, so the
  # new row simply appears for every existing member — and turns off in
  # Settings like any other.
  def up
    return if select_value("SELECT 1 FROM sections WHERE slug = 'travel'")

    now = Time.current.utc.iso8601
    execute <<~SQL.squish
      INSERT INTO sections (slug, name, position, custom, created_at, updated_at)
      VALUES ('travel', 'Travel', 8, 0, '#{now}', '#{now}')
    SQL
  end

  def down
    # Tagging rows go with it (section_taggings has the foreign key), which
    # is the point of a down: the tag disappears, the items don't.
    execute "DELETE FROM section_taggings WHERE section_id IN (SELECT id FROM sections WHERE slug = 'travel')"
    execute "DELETE FROM user_sections WHERE section_id IN (SELECT id FROM sections WHERE slug = 'travel')"
    execute "DELETE FROM access_grants WHERE subject_type = 'Section' AND subject_id IN (SELECT id FROM sections WHERE slug = 'travel')"
    execute "DELETE FROM sections WHERE slug = 'travel'"
  end
end
