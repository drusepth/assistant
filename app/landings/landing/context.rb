module Landing
  # Everything a kind needs to know about *whose* rows it is proposing
  # (D-landing-registry): the user, the document's filing, and the closed
  # lists that reference fields resolve against — rendered from what this
  # user can see, so a household member's unshared pets and people never
  # appear in a listing and can never be referenced.
  class Context
    MAX_LISTED = 40

    def initialize(user:, document: nil)
      @user = user
      @document = document
    end

    attr_reader :user, :document

    # The filing a landing inherits: the document's sections (INTAKE_PLAN
    # §2, "a landing inherits the document's filing").
    def filing = document ? document.sections.to_a : []

    # ── References ───────────────────────────────────────────────────

    # [label, key] pairs for a ref field's select; the same keys the prompt
    # listing names.
    def ref_options(ref)
      case ref.to_sym
      when :pet then pets.map { |pet| [ pet_label(pet), pet.section.slug ] }
      when :person then people.map { |person| [ person_label(person), person.id.to_s ] }
      else []
      end
    end

    # The record a key names, through the visibility wall, or nil.
    def resolve(ref, key)
      return nil if key.blank?

      case ref.to_sym
      when :pet then pets.find { |pet| pet.section.slug == key.to_s }
      when :person then people.find { |person| person.id.to_s == key.to_s }
      end
    end

    # The prompt's listing for a ref, or nil when there is nothing to list.
    def ref_listing(ref)
      options = ref_options(ref)
      return nil if options.empty?

      heading = { pet: "The household's pets (key — who)", person: "People the user knows (key — who)" }[ref.to_sym]
      "#{heading}:\n#{options.map { |label, key| "#{key} — #{label}" }.join("\n")}"
    end

    def pets
      @pets ||= Pet.visible_to(user).active.includes(:section).limit(MAX_LISTED).to_a
    end

    def people
      @people ||= Person.visible_to(user).order(:name).limit(MAX_LISTED).to_a
    end

    private
      def pet_label(pet)
        [ pet.name, pet.species_label.downcase, pet.breed.presence ].compact.join(", ")
      end

      def person_label(person)
        [ person.name, person.relationship.presence ].compact.join(" — ")
      end
  end
end
