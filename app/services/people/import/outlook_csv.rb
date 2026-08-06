# Outlook / Windows Contacts CSV export: one flat row per contact with fixed
# columns ("E-mail Address", "Mobile Phone", "Home Street"/"Home City"/…).
class People::Import::OutlookCsv < People::Import::CsvBase
  def self.handles_headers?(headers)
    headers.include?("E-mail Address") ||
      (headers.include?("First Name") && headers.include?("Mobile Phone"))
  end

  PHONE_COLUMNS = {
    "Mobile Phone" => "mobile", "Home Phone" => "home", "Home Phone 2" => "home",
    "Business Phone" => "work", "Business Phone 2" => "work", "Primary Phone" => nil,
    "Other Phone" => nil, "Company Main Phone" => "work", "Car Phone" => nil, "Pager" => "pager"
  }.freeze

  EMAIL_COLUMNS = { "E-mail Address" => nil, "E-mail 2 Address" => nil, "E-mail 3 Address" => nil }.freeze

  ADDRESS_GROUPS = { "Home" => "home", "Business" => "work", "Other" => nil }.freeze

  private
    def build_contact(row)
      contact = People::Import::Contact.new(
        name: join_present(row["First Name"], row["Middle Name"], row["Last Name"]) || row["Company"],
        birthday: parse_date(row["Birthday"]),
        organization: organization(row),
        notes: row["Notes"]
      )

      PHONE_COLUMNS.each do |column, label|
        contact.phones << People::Import::Labeled.new(label, row[column]) if row[column].present?
      end
      EMAIL_COLUMNS.each_key do |column|
        contact.emails << People::Import::Labeled.new(nil, row[column]) if row[column].present?
      end
      ADDRESS_GROUPS.each do |prefix, label|
        address = join_address(row, prefix)
        contact.addresses << People::Import::Labeled.new(label, address) if address.present?
      end
      contact
    end

    def organization(row)
      company = row["Company"]
      title = row["Job Title"]
      return company unless title.present?
      company.present? ? "#{company} (#{title})" : title
    end

    def join_address(row, prefix)
      parts = [
        row["#{prefix} Street"], row["#{prefix} Street 2"], row["#{prefix} Street 3"],
        row["#{prefix} City"], row["#{prefix} State"], row["#{prefix} Postal Code"],
        row["#{prefix} Country/Region"] || row["#{prefix} Country"]
      ]
      parts.compact.reject(&:blank?).map { |part| part.gsub(/\s*\n\s*/, ", ") }.join(", ").presence
    end
end
