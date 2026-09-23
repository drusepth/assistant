module Landing
  # The amendment kind (D-landing-registry): a vet sheet states a weight, a
  # microchip number, a date of birth, the practice — facts that belong on
  # the Pet row, not in a new one. `land!` updates the pet the ref names and
  # the preview shows old → new, so the review page makes the replacement
  # visible before it happens. A blank field on the form leaves the current
  # value alone (the D16 hand-set guard, made per-field).
  class PetFacts < Base
    self.description = "facts about a pet that update her record: current weight, microchip number, date of birth, or the vet"
    self.produces = "pets"
    self.amends = true

    field :pet, "which pet", type: :ref, ref: :pet, required: true
    field :weight_kg, "current weight in kilograms, as printed (convert lb to kg only if the document gives no kg figure)", type: :decimal
    field :microchip, "the microchip number, digits as printed"
    field :born_on, "date of birth, only if the document states one", type: :date
    field :vet, "the vet or practice, if they are one of the people listed", type: :ref, ref: :person

    def self.label = "updates the pet"

    def land!(attributes, sections:)
      pet = context.resolve(:pet, attributes["pet"])
      raise ActiveRecord::RecordNotFound, "that pet is gone or no longer shared" unless pet && pet.user_id == user.id

      changes = {}
      changes[:weight_kg] = attributes["weight_kg"] if attributes["weight_kg"].present?
      changes[:microchip] = attributes["microchip"] if attributes["microchip"].present?
      changes[:born_on] = attributes["born_on"] if attributes["born_on"].present?
      if attributes["vet"].present? && (vet = context.resolve(:person, attributes["vet"]))
        changes[:vet] = vet
      end
      pet.update!(changes) if changes.any?
      pet
    end

    # Old → new, one line per field that would change.
    def amendments(attributes)
      pet = context.resolve(:pet, attributes["pet"]) or return []
      lines = []
      if attributes["weight_kg"].present?
        # Stored and read in kg; shown in the unit the user reads.
        units = user.units
        lines << [ "Weight", units.weight_phrase(pet.weight_kg), units.weight_phrase(attributes["weight_kg"].to_d) ]
      end
      lines << [ "Microchip", pet.microchip.presence, attributes["microchip"] ] if attributes["microchip"].present?
      lines << [ "Born", pet.born_on&.iso8601, attributes["born_on"] ] if attributes["born_on"].present?
      if attributes["vet"].present? && (vet = context.resolve(:person, attributes["vet"]))
        lines << [ "Vet", pet.vet&.name, vet.name ]
      end
      lines.reject { |_label, old, new| old == new }
    end

    def preview(attributes)
      pet = context.resolve(:pet, attributes["pet"])
      detail = amendments(attributes).map { |label, old, new| "#{label}: #{old || "—"} → #{new}" }.join("\n")
      Preview.new(kind: kind, title: pet ? "#{pet.name}'s record" : "A pet's record", detail: detail.presence, date: nil)
    end

    def fingerprint(attributes)
      "pet_facts:#{attributes["pet"]}:#{attributes.slice("weight_kg", "microchip", "born_on", "vet").values.map { |v| v.to_s.parameterize }.join(":")}"
    end
  end
end
