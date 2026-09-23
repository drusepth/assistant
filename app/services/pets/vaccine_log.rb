module Pets
  # The log form's write (D-pet-vaccinations): one visit, several vaccines.
  # A real visit is one date, one vet, one certificate and three or four
  # shots, so the form asks for the visit once and a row per vaccine, and
  # this writes one PetVaccination per ticked row — all of them or none.
  #
  # `rows` is the form's per-vaccine params, keyed by the catalog key for a
  # listed vaccine or "other_N" for a typed one; a row lands only when its
  # box is ticked. A typed good-until date is the certificate's and wins over
  # a picked duration, so the duration is cleared rather than left to
  # silently recompute the date on a later edit.
  class VaccineLog
    include ActiveModel::Model

    ROW_FIELDS = %i[ include vaccine_key name kind due_on duration_months product lot_number
                     tag_number site series_dose reaction notes ].freeze
    VISIT_FIELDS = %i[ given_on vet_id administered_by event_id document_id certificate ].freeze
    OTHER_ROWS = 3

    attr_accessor :pet, :user, :given_on, :vet_id, :administered_by, :event_id, :document_id, :certificate
    attr_writer :rows
    attr_reader :doses

    def rows = (@rows || {}).to_h.transform_keys(&:to_s).transform_values { |row| row.to_h.stringify_keys }

    def row(key) = rows[key.to_s] || {}
    def ticked?(key) = row(key)["include"].to_s == "1"

    # The catalog rows, then the typed ones — what the form renders.
    def catalog = Pets::Vaccines.for(pet.species)
    def other_keys = (0...OTHER_ROWS).map { |index| "other_#{index}" }

    def event = event_id.present? ? Event.visible_to(user).in_section(pet.section_id).find_by(id: event_id) : nil
    def document = document_id.present? ? Document.visible_to(user).find_by(id: document_id) : nil
    def vet = vet_id.present? ? Person.visible_to(user).find_by(id: vet_id) : nil

    def save
      @doses = build_doses
      errors.add(:base, "Tick at least one vaccine") if @doses.empty?
      errors.add(:given_on, "is required") if given_on.blank?
      @doses.each do |dose|
        next if dose.valid?

        dose.errors.full_messages.each { |message| errors.add(:base, "#{dose.name.presence || "A vaccine"}: #{message}") }
      end
      return false if errors.any?

      PetVaccination.transaction do
        certificate_document = attach_certificate
        @doses.each do |dose|
          dose.document = certificate_document if certificate_document
          dose.save!
        end
        mark_visit
      end
      true
    end

    private
      def build_doses
        rows.filter_map do |key, attrs|
          next unless attrs["include"].to_s == "1"

          catalog_key = key.start_with?("other_") ? nil : key
          next if catalog_key.nil? && attrs["name"].blank?

          due_on = attrs["due_on"].presence
          pet.pet_vaccinations.new(
            user: user, kind: attrs["kind"].presence || "dose",
            vaccine_key: catalog_key, name: attrs["name"].presence,
            given_on: given_on.presence, due_on: due_on,
            duration_months: due_on ? nil : attrs["duration_months"].presence,
            vet: vet, administered_by: administered_by.presence,
            product: attrs["product"].presence, lot_number: attrs["lot_number"].presence,
            tag_number: attrs["tag_number"].presence, site: attrs["site"].presence,
            series_dose: attrs["series_dose"].presence,
            reaction: attrs["reaction"].presence, notes: attrs["notes"].presence,
            document: document, event: event
          )
        end
      end

      # A scan uploaded on the form becomes an ordinary vault document filed
      # under Health and her name, the way her papers already are. Not sent
      # for analysis: the owner just typed what it says, and intake would
      # only propose the same doses back as duplicates.
      def attach_certificate
        return nil unless certificate.respond_to?(:original_filename)

        document = user.documents.create!(file: certificate,
          title: "#{pet.name} — vaccination certificate, #{Date.iso8601(given_on.to_s).strftime("%B %-d, %Y")}")
        document.sections = [ Section.find_by(slug: "health"), pet.section ].compact
        document
      end

      # The visit said what it was only in its title; now it says so in the
      # field the radar reads, so it leaves the wellness tile alone.
      def mark_visit
        visit = event
        return unless visit && visit.user_id == user.id && visit.care_kind.blank?

        visit.update!(care_kind: Pets::VaccineStatus::VISIT_KIND)
      end
  end
end
