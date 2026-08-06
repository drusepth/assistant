# Contacts picked straight from the phone via the browser Contact Picker API
# (the mobile path on the import page — no export file needed). The Stimulus
# controller serializes the picker's output to a JSON array whose shapes
# mirror the API: name/tel/email are arrays of strings, address is an array
# of ContactAddress-shaped hashes. The picker carries no type labels, so all
# values are unlabeled.
class People::Import::DeviceJson
  def self.handles?(filename, content)
    return false unless filename.to_s.match?(/\.json\z/i) || content.lstrip.start_with?("[")

    parsed = JSON.parse(content)
    parsed.is_a?(Array) && parsed.all?(Hash)
  rescue JSON::ParserError
    false
  end

  def initialize(content)
    @content = content
  end

  def contacts
    JSON.parse(@content).map { |entry| build_contact(entry) }
  end

  private
    def build_contact(entry)
      contact = People::Import::Contact.new
      contact.name = strings(entry["name"]).first
      contact.phones = strings(entry["tel"]).map { |v| People::Import::Labeled.new(nil, v) }
      contact.emails = strings(entry["email"]).map { |v| People::Import::Labeled.new(nil, v) }
      contact.addresses = Array(entry["address"]).filter_map do |address|
        value = formatted_address(address)
        People::Import::Labeled.new(nil, value) if value.present?
      end
      contact
    end

    def strings(values)
      Array(values).map { |v| v.to_s.strip }.reject(&:blank?)
    end

    def formatted_address(address)
      return address.to_s.strip unless address.is_a?(Hash)

      parts = Array(address["addressLine"]) + address.values_at("city", "region", "postalCode", "country")
      parts.map { |p| p.to_s.strip }.reject(&:blank?).join(", ")
    end
end
