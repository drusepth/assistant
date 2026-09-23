class AddPetsSection < ActiveRecord::Migration[8.1]
  # Pets is the ninth top-level section (D-pets-section), and every pet's lens
  # moves under it from People. db/seeds.rb carries the row for fresh
  # installs; this migration is how running boxes get it, since nobody
  # re-runs seeds on an upgrade.
  #
  # Moving a lens changes only its parent: its slug, its taggings and any
  # grant on it stay put, so every item filed under a pet's name keeps it.
  def up
    pets_id = select_value("SELECT id FROM sections WHERE slug = 'pets' AND parent_id IS NULL")

    unless pets_id
      # A user-made lens may already hold the slug (a group or hobby someone
      # called "Pets"). The seeded taxonomy wins the global namespace, and
      # the lens takes a numbered slug the way `Sections::Lens` would have
      # given it one had the seed come first.
      if select_value("SELECT 1 FROM sections WHERE slug = 'pets'")
        counter = 2
        counter += 1 while select_value("SELECT 1 FROM sections WHERE slug = 'pets-#{counter}'")
        execute "UPDATE sections SET slug = 'pets-#{counter}' WHERE slug = 'pets'"
      end

      now = Time.current.utc.iso8601
      execute <<~SQL.squish
        INSERT INTO sections (slug, name, position, custom, created_at, updated_at)
        VALUES ('pets', 'Pets', 9, 0, '#{now}', '#{now}')
      SQL
      pets_id = select_value("SELECT id FROM sections WHERE slug = 'pets'")
    end

    execute <<~SQL.squish
      UPDATE sections SET parent_id = #{pets_id}
      WHERE id IN (SELECT section_id FROM pets WHERE section_id IS NOT NULL)
    SQL
  end

  def down
    people_id = select_value("SELECT id FROM sections WHERE slug = 'people'")
    pets_id = select_value("SELECT id FROM sections WHERE slug = 'pets' AND parent_id IS NULL")
    return unless pets_id

    # The lenses go home first, so deleting the section can't take them —
    # and the pets' tags — with it.
    execute "UPDATE sections SET parent_id = #{people_id || "NULL"} WHERE parent_id = #{pets_id}"
    execute "DELETE FROM section_taggings WHERE section_id = #{pets_id}"
    execute "DELETE FROM user_sections WHERE section_id = #{pets_id}"
    execute "DELETE FROM access_grants WHERE subject_type = 'Section' AND subject_id = #{pets_id}"
    execute "DELETE FROM sections WHERE id = #{pets_id}"
  end
end
