module Landing
  # The vet, the landlord, the specialist, the case worker — a contact the
  # document names with a way to reach them. Lands in the Address Book as
  # an ordinary Person, so it is callable and attachable from then on.
  class Person < Base
    self.description = "a person or organisation the document names as someone to contact, with their details"
    self.produces = "people"

    field :name, "as printed", required: true
    field :relationship, "their role to the reader, e.g. Vet, Landlord, Doctor"
    field :phone
    field :email
    field :address, type: :text, limit: 500
    field :notes, "anything else the document says about them", type: :text

    def land!(attributes, sections:)
      person = user.people.create!(attributes.slice("name", "relationship", "phone", "email", "address", "notes"))
      tag(person, sections)
    end

    def duplicate_of(attributes)
      ::Person.visible_to(user).where("LOWER(people.name) = ?", attributes["name"].to_s.downcase).first
    end

    def preview(attributes)
      detail = [ attributes["relationship"], attributes["phone"], attributes["email"] ].compact_blank.join(" · ")
      Preview.new(kind: kind, title: attributes["name"], detail: detail.presence, date: nil)
    end

    def self.label = "contact"

    private
      def key_fields = %w[ name ]
  end
end
