module Landing
  # A dose read off a rabies certificate or a clinic invoice
  # (D-pet-vaccinations) — the most common pet document there is. One entry
  # per vaccine given; nothing lands without the click, and the document it
  # came from is linked to the dose as its certificate.
  #
  # The model maps a printed name ("Nobivac 3-Rabies", "DA2PP") onto the
  # catalog *inside the closed set* — classification by the model over a
  # bounded list, which is what D-no-keyword-logic asks for. A key that turns
  # out not to fit the resolved pet's species lands as a free-text vaccine
  # under its printed name rather than being forced into the wrong row.
  #
  # Not proposed: a reaction or notes. Those are the owner's words, and a
  # model inferring "no reaction" from a certificate's silence would put a
  # false sentence on the page the next vet reads.
  class PetVaccination < Base
    self.description = "a vaccine a pet was given (or a titer test or vet exemption in place of one), " \
                       "as on a vaccination certificate, rabies certificate or vet invoice"
    self.produces = "pet_vaccinations"

    OTHER = "other".freeze

    field :pet, "which pet", type: :ref, ref: :pet, required: true
    field :vaccine, "the vaccine, matched to this list by what it protects against; \"other\" if none fits",
      type: :choice, choices: ->(_context) { [ *Pets::Vaccines.all_keys.map { |key| [ Pets::Vaccines.label_for(key), key ] }, [ "Other", OTHER ] ] }
    field :name, "the vaccine as printed", required: true
    field :kind, "dose for a vaccination; titer for a blood test showing immunity; exemption for a vet's waiver",
      type: :choice, choices: ::PetVaccination::KINDS
    field :given_on, "the date it was given or drawn", type: :date, required: true
    field :due_on, "the expiry, next-due or valid-until date, only if printed", type: :date
    field :product, "brand or manufacturer, as printed"
    field :lot_number, "lot or serial number, as printed"
    field :tag_number, "rabies tag or certificate number, as printed"
    field :administered_by, "the vet or clinic that gave it, as printed"
    field :site, "where on the body it was given, only if printed"
    field :series_dose, "which dose in a puppy/kitten series, only if stated", type: :integer

    def self.label = "vaccination"

    def land!(attributes, sections:)
      pet = context.resolve(:pet, attributes["pet"])
      raise ActiveRecord::RecordNotFound, "that pet is gone or no longer shared" unless pet

      pet.pet_vaccinations.create!(
        user: user, kind: attributes["kind"].presence || "dose",
        vaccine_key: vaccine_key_for(pet, attributes["vaccine"]), name: attributes["name"],
        given_on: parsed_date(attributes["given_on"]), due_on: parsed_date(attributes["due_on"]),
        product: attributes["product"], lot_number: attributes["lot_number"], tag_number: attributes["tag_number"],
        administered_by: attributes["administered_by"], site: attributes["site"], series_dose: attributes["series_dose"],
        document: context.document
      )
    end

    # The same certificate uploaded twice, or two documents stating one dose:
    # the same pet, the same vaccine, the same day.
    def duplicate_of(attributes)
      pet = context.resolve(:pet, attributes["pet"]) or return nil
      given_on = parsed_date(attributes["given_on"]) or return nil

      group = ::PetVaccination.group_key_for(vaccine_key_for(pet, attributes["vaccine"]), attributes["name"])
      pet.pet_vaccinations.where(given_on: given_on).detect { |dose| dose.group_key == group }
    end

    def preview(attributes)
      pet = context.resolve(:pet, attributes["pet"])
      label = Pets::Vaccines.label_for(attributes["vaccine"]) if attributes["vaccine"].present? && attributes["vaccine"] != OTHER
      title = [ label, attributes["name"] ].compact.uniq(&:downcase).join(" — ")
      kind = attributes["kind"].presence && attributes["kind"] != "dose" ? ::PetVaccination::KIND_LABELS[attributes["kind"]] : nil
      detail = [ pet && "for #{pet.name}", kind,
                 attributes["due_on"] && "good until #{attributes["due_on"]}",
                 attributes["tag_number"] && "tag #{attributes["tag_number"]}" ].compact_blank.join(" · ")
      Preview.new(kind: kind_name, title: title, detail: detail.presence, date: attributes["given_on"])
    end

    private
      def kind_name = self.class.kind
      def key_fields = %w[ pet vaccine name given_on ]

      def vaccine_key_for(pet, key)
        return nil if key.blank? || key == OTHER

        Pets::Vaccines.find(pet.species, key) ? key : nil
      end
  end
end
