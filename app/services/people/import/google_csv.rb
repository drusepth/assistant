# Google Contacts CSV export. Covers both the current export ("First Name",
# "Phone 1 - Label"/"Phone 1 - Value", "Organization Name") and the older one
# ("Given Name", "Phone 1 - Type"/"Phone 1 - Value", "Organization 1 - Name").
# Relation columns describe people related to the contact (their spouse, their
# mother) — not the contact's relationship to the user — so they go to notes.
class People::Import::GoogleCsv < People::Import::CsvBase
  def self.handles_headers?(headers)
    headers.any? { |h| h.match?(/\A(Phone|E-mail) \d+ - Value\z/) }
  end

  private
    def build_contact(row)
      contact = People::Import::Contact.new(
        name: row["Name"] || join_present(row["First Name"], row["Middle Name"], row["Last Name"]) ||
              join_present(row["Given Name"], row["Additional Name"], row["Family Name"]),
        birthday: parse_date(row["Birthday"]),
        organization: row["Organization Name"] || row["Organization 1 - Name"],
        notes: [ row["Notes"], *relation_lines(row) ].compact.join("\n").presence
      )

      numbered(row, "Phone", "Value") { |label, value| contact.phones << labeled(label, value) }
      numbered(row, "E-mail", "Value") { |label, value| contact.emails << labeled(label, value) }
      numbered(row, "Address", "Formatted") do |label, value|
        contact.addresses << labeled(label, value.gsub(/\s*\n\s*/, ", "))
      end
      contact
    end

    # Google columns come in numbered groups: "Phone 1 - Value" with a
    # sibling "Phone 1 - Label" (current) or "Phone 1 - Type" (older).
    def numbered(row, prefix, value_suffix)
      1.step do |i|
        value_key = "#{prefix} #{i} - #{value_suffix}"
        break unless row.key?(value_key)

        label = row["#{prefix} #{i} - Label"] || row["#{prefix} #{i} - Type"]
        # Google packs multiple values into one cell separated by " ::: "
        row[value_key].to_s.split(" ::: ").map(&:strip).reject(&:blank?).each do |value|
          yield label, value
        end
      end
    end

    def relation_lines(row)
      lines = []
      numbered(row, "Relation", "Value") do |label, value|
        prefix = label.to_s.delete_prefix("* ").strip.presence || "Related"
        lines << "#{prefix.capitalize}: #{value}"
      end
      lines
    end

    def labeled(label, value)
      cleaned = label.to_s.delete_prefix("* ").strip.downcase.presence
      People::Import::Labeled.new(cleaned, value)
    end
end
