module Landing
  # An allergy is a Note with kind "allergy" carrying a severity (HEALTH.md
  # §8, D-allergy-notes). Severity comes from the closed set or is left
  # unanswered — a guessed severity is worse than a missing one.
  class Allergy < Base
    self.description = "an allergy or adverse reaction the document records for the reader (or a pet)"
    self.produces = "notes"

    field :allergen, "what they react to, as printed", required: true
    field :reaction, "what happens, as printed"
    field :severity, "only when the document says how serious it is", type: :choice, choices: ::Note::SEVERITIES
    field :pet, "the pet it is about, if it is a pet's", type: :ref, ref: :pet

    def land!(attributes, sections:)
      note = user.notes.create!(
        kind: ::Note::ALLERGY, title: attributes["allergen"],
        body: attributes["reaction"].presence || attributes["allergen"],
        severity: attributes["severity"].presence
      )
      tag(note, with_pet(sections, attributes))
    end

    def duplicate_of(attributes)
      ::Note.visible_to(user).allergies.where("LOWER(notes.title) = ?", attributes["allergen"].to_s.downcase).first
    end

    def preview(attributes)
      detail = [ attributes["reaction"], attributes["severity"]&.humanize ].compact_blank.join(" · ")
      Preview.new(kind: kind, title: attributes["allergen"], detail: detail.presence, date: nil)
    end

    def default_sections = [ Section.find_by(slug: "health") ].compact

    private
      def key_fields = %w[ allergen pet ]
  end
end
