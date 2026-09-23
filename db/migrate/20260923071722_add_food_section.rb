class AddFoodSection < ActiveRecord::Migration[8.1]
  # Food is the tenth top-level section (D-food-section). db/seeds.rb carries
  # the row for fresh installs; this migration is how running boxes get it,
  # since nobody re-runs seeds on an upgrade.
  def up
    return if select_value("SELECT 1 FROM sections WHERE slug = 'food' AND parent_id IS NULL")

    # A user-made lens may already hold the slug (a hobby someone called
    # "Food"). The seeded taxonomy wins the global namespace, and the lens
    # takes a numbered slug — the AddPetsSection rule.
    if select_value("SELECT 1 FROM sections WHERE slug = 'food'")
      counter = 2
      counter += 1 while select_value("SELECT 1 FROM sections WHERE slug = 'food-#{counter}'")
      execute "UPDATE sections SET slug = 'food-#{counter}' WHERE slug = 'food'"
    end

    now = Time.current.utc.iso8601
    execute <<~SQL.squish
      INSERT INTO sections (slug, name, position, custom, created_at, updated_at)
      VALUES ('food', 'Food', 10, 0, '#{now}', '#{now}')
    SQL
  end

  def down
    food_id = select_value("SELECT id FROM sections WHERE slug = 'food' AND parent_id IS NULL")
    return unless food_id

    execute "DELETE FROM section_taggings WHERE section_id = #{food_id}"
    execute "DELETE FROM user_sections WHERE section_id = #{food_id}"
    execute "DELETE FROM access_grants WHERE subject_type = 'Section' AND subject_id = #{food_id}"
    execute "DELETE FROM sections WHERE id = #{food_id}"
  end
end
