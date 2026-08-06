# Imports an address-book export into the user's People. Modular by design:
# each format is a parser class in People::Import:: that answers `handles?`
# and emits normalized Contacts; adding a format means adding a parser to
# FORMATS. Everything funnels through the same Person-building code here.
class People::Import
  # What every parser emits, regardless of source format. phones/emails/
  # addresses are arrays of Labeled values because real address books carry
  # several of each; the first becomes the Person column, the rest land in
  # notes so nothing is dropped.
  Contact = Struct.new(
    :name, :relationship, :phones, :emails, :addresses,
    :birthday, :organization, :notes,
    keyword_init: true
  ) do
    def initialize(**args)
      super
      self.phones ||= []
      self.emails ||= []
      self.addresses ||= []
    end
  end

  Labeled = Struct.new(:label, :value)

  Result = Struct.new(:imported, :skipped, :error, keyword_init: true)

  # Ordered: specific formats first, the header-sniffing generic CSV last.
  FORMATS = [
    People::Import::Vcard,
    People::Import::GoogleCsv,
    People::Import::OutlookCsv,
    People::Import::GenericCsv
  ].freeze

  def initialize(user:, file:)
    @user = user
    @filename = file.respond_to?(:original_filename) ? file.original_filename : File.basename(file.to_path)
    @content = normalize_encoding(file.read)
  end

  def call
    parser = FORMATS.find { |format| format.handles?(@filename, @content) }
    unless parser
      return Result.new(imported: 0, skipped: 0,
        error: "That file doesn't look like an address book export. Use a vCard (.vcf) or CSV export from your contacts app.")
    end

    contacts = parser.new(@content).contacts.select { |c| c.name.present? }
    if contacts.empty?
      return Result.new(imported: 0, skipped: 0, error: "No contacts found in that file.")
    end

    import(contacts)
  end

  private
    def import(contacts)
      existing = @user.people.pluck(:name).to_set { |n| n.downcase.squish }
      imported = 0
      skipped = 0

      Person.transaction do
        contacts.each do |contact|
          key = contact.name.downcase.squish
          if existing.include?(key)
            skipped += 1
            next
          end
          existing << key

          person = @user.people.create!(person_attributes(contact))
          person.sections = [ people_section ].compact
          imported += 1
        end
      end

      Result.new(imported: imported, skipped: skipped)
    end

    def person_attributes(contact)
      {
        name: contact.name.squish,
        relationship: contact.relationship.presence,
        phone: contact.phones.first&.value,
        email: contact.emails.first&.value,
        address: contact.addresses.first&.value,
        birthday: contact.birthday,
        notes: composed_notes(contact)
      }
    end

    # Everything that doesn't fit the Person columns — extra numbers, second
    # addresses, employer — is kept as readable lines rather than thrown away.
    def composed_notes(contact)
      lines = []
      lines << contact.notes if contact.notes.present?
      lines << "Company: #{contact.organization}" if contact.organization.present?
      lines.concat(overflow_lines("phone", contact.phones.drop(1)))
      lines.concat(overflow_lines("email", contact.emails.drop(1)))
      lines.concat(overflow_lines("address", contact.addresses.drop(1)))
      lines.join("\n").presence
    end

    def overflow_lines(kind, labeled_values)
      labeled_values.map do |labeled|
        prefix = labeled.label.present? ? labeled.label.capitalize : "Other"
        "#{prefix} #{kind}: #{labeled.value}"
      end
    end

    def people_section
      return @people_section if defined?(@people_section)
      @people_section = Section.find_by(slug: "people")
    end

    def normalize_encoding(raw)
      raw.force_encoding(Encoding::UTF_8)
      raw = raw.valid_encoding? ? raw : raw.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
      raw.delete_prefix("\u{FEFF}").scrub
    end
end
