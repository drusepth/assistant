# D-pet-vaccinations retires the care radar's keyword-matched "Vaccinations"
# kind. Pet events the old radar counted as vaccination visits get that
# answer written down once, as the explicit `care_kind` the user could always
# have set, so the new card can ask what was given at them — and so they don't
# fall through to the wellness kind's patterns. This is the last time those
# patterns run; nothing at runtime matches titles for vaccines.
class MarkPetVaccinationVisits < ActiveRecord::Migration[8.1]
  OLD_PATTERNS = [ /vaccin/, /\bshots?\b/, /booster/, /rabies/, /\bjab\b/ ].freeze

  def up
    lens_ids = select_values("SELECT section_id FROM pets")
    return if lens_ids.empty?

    rows = select_rows(<<~SQL)
      SELECT DISTINCT events.id, events.title FROM events
      JOIN section_taggings ON section_taggings.taggable_type = 'Event' AND section_taggings.taggable_id = events.id
      WHERE section_taggings.section_id IN (#{lens_ids.map(&:to_i).join(",")})
        AND (events.care_kind IS NULL OR events.care_kind = '')
    SQL
    ids = rows.select { |_id, title| OLD_PATTERNS.any? { |pattern| title.to_s.downcase.match?(pattern) } }.map(&:first)
    execute("UPDATE events SET care_kind = 'pet_vaccinations' WHERE id IN (#{ids.map(&:to_i).join(",")})") if ids.any?
  end

  def down
  end
end
