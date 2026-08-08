# LinkedIn's official data export — the honest path to LinkedIn data (D27:
# the API is closed to non-partners, so the user downloads their archive and
# uploads Connections.csv here). It carries name, company, position, and the
# connection date; newer exports open with a "Notes:" preamble paragraph
# before the header row, so this parser finds the header before sniffing.
class People::Import::LinkedinCsv < People::Import::CsvBase
  def self.handles?(_filename, content)
    header_index(content).present?
  end

  def self.header_index(content)
    content.lines.first(10).index do |line|
      line.start_with?("First Name,") && line.include?("Connected On")
    end
  end

  def initialize(content)
    super(content.lines.drop(self.class.header_index(content).to_i).join)
  end

  private
    def build_contact(row)
      contact = People::Import::Contact.new(
        name: join_present(row["First Name"], row["Last Name"]),
        organization: row["Company"],
        notes: [
          row["Position"].presence && "Position: #{row["Position"]}",
          row["Connected On"].presence && "Connected on LinkedIn: #{row["Connected On"]}",
          row["URL"].presence && "LinkedIn: #{row["URL"]}"
        ].compact.join("\n").presence
      )
      contact.emails << People::Import::Labeled.new(nil, row["Email Address"]) if row["Email Address"].present?
      contact
    end
end
