module Landing
  # A medication is a Note with kind "medication" (HEALTH.md §7, D36) plus
  # an optional all-day refill Event the radar ignores — exactly what the
  # Medications card's add form writes, so a medication read off a
  # discharge sheet and one typed in are the same rows.
  class Medication < Base
    self.description = "a medication the reader (or a pet) is on or has been prescribed"
    self.produces = "notes"

    field :name, "the medication, as printed", required: true
    field :dose_and_schedule, "dose and how often, as printed, e.g. \"5 mg, twice a day with food\""
    field :refill_on, "only when a refill or repeat date is stated", type: :date
    field :pet, "the pet it is for, if it is a pet's", type: :ref, ref: :pet

    def land!(attributes, sections:)
      sections = with_pet(sections, attributes)
      note = user.notes.create!(
        kind: ::Note::MEDICATION, title: attributes["name"],
        body: attributes["dose_and_schedule"].presence || attributes["name"]
      )
      tag(note, sections)

      if (refill_on = parsed_date(attributes["refill_on"]))
        event = user.events.create!(title: "Refill #{attributes["name"]}", starts_at: refill_on.in_time_zone,
          all_day: true, care_kind: Health::CareRadar::EXCLUDED)
        tag(event, sections)
      end
      note
    end

    def duplicate_of(attributes)
      ::Note.visible_to(user).medications.where("LOWER(notes.title) = ?", attributes["name"].to_s.downcase).first
    end

    def preview(attributes)
      Preview.new(kind: kind, title: attributes["name"], detail: attributes["dose_and_schedule"], date: attributes["refill_on"])
    end

    def default_sections = [ Section.find_by(slug: "health") ].compact

    private
      def key_fields = %w[ name pet ]
  end
end
