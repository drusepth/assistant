# vCard (.vcf) parser covering the 2.1/3.0/4.0 exports produced by iCloud,
# iPhone, Android, Google, macOS Contacts, and Outlook: folded lines,
# quoted-printable (2.1), escaped values, grouped properties (item1.TEL),
# and multi-valued TEL/EMAIL/ADR with type labels.
class People::Import::Vcard
  def self.handles?(filename, content)
    filename.to_s.match?(/\.(vcf|vcard)\z/i) || content.lstrip.start_with?("BEGIN:VCARD")
  end

  def initialize(content)
    @content = content
  end

  def contacts
    cards.map { |properties| build_contact(properties) }
  end

  private
    # Splits into cards, each an array of [name, params, value] property
    # triples with folding and encodings already resolved.
    def cards
      result = []
      current = nil

      unfolded_lines.each do |line|
        name, params, value = parse_property(line)
        next unless name

        case name
        when "BEGIN" then current = []
        when "END"   then result << current if current&.any?; current = nil
        else current << [ name, params, value ] if current
        end
      end

      result
    end

    def unfolded_lines
      lines = @content.split(/\r?\n/)
      unfolded = []

      lines.each do |line|
        if line.start_with?(" ", "\t") && unfolded.any?
          unfolded[-1] += line[1..] # RFC folding: leading whitespace continues the line
        elsif unfolded.any? && unfolded.last.match?(/ENCODING=QUOTED-PRINTABLE/i) && unfolded.last.end_with?("=")
          unfolded[-1] = unfolded.last.delete_suffix("=") + line # QP soft line break (vCard 2.1)
        else
          unfolded << line
        end
      end

      unfolded
    end

    def parse_property(line)
      head, _, value = line.partition(":")
      return nil if value.empty? && !line.include?(":")

      parts = head.split(";")
      name = parts.shift.to_s.sub(/\A[^.]+\./, "").upcase # strip item1. grouping
      return nil if name.empty?

      params = parts.map { |p| p.include?("=") ? p.split("=", 2) : [ "TYPE", p ] }
                    .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(k, v), h| h[k.upcase].concat(v.to_s.split(",")) }

      [ name, params, decode_value(value, params) ]
    end

    def decode_value(value, params)
      if params["ENCODING"].any? { |e| e.casecmp?("QUOTED-PRINTABLE") }
        charset = params["CHARSET"].first || "UTF-8"
        value.unpack1("M").force_encoding(charset).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      else
        value
      end
    end

    # \, \; \n \\ escapes (RFC 6350); applied per-field after splitting.
    def unescape(value)
      value.to_s.gsub(/\\([\\,;nN])/) { |m| m[1].casecmp?("n") ? "\n" : m[1] }
    end

    # Splits on semicolons that aren't escaped.
    def split_fields(value)
      value.split(/(?<!\\);/, -1)
    end

    def build_contact(properties)
      contact = People::Import::Contact.new

      properties.each do |name, params, value|
        case name
        when "FN"    then contact.name ||= unescape(value).strip
        when "N"     then contact.name ||= structured_name(value)
        when "TEL"   then contact.phones << labeled(params, unescape(value).strip)
        when "EMAIL" then contact.emails << labeled(params, unescape(value).strip)
        when "ADR"   then contact.addresses << labeled(params, formatted_address(value))
        when "ORG"   then contact.organization = split_fields(value).map { |f| unescape(f).strip }.reject(&:blank?).join(", ")
        when "NOTE"  then contact.notes = [ contact.notes, unescape(value).strip ].compact.join("\n")
        when "BDAY"  then assign_birthday(contact, value)
        when "PHOTO" then contact.photo ||= photo(params, value)
        end
      end

      contact.name ||= structured_name_fallback(properties)
      contact.phones.reject! { |p| p.value.blank? }
      contact.emails.reject! { |p| p.value.blank? }
      contact.addresses.reject! { |p| p.value.blank? }
      contact
    end

    # PHOTO comes three ways: base64 with ENCODING=BASE64 (2.1) or
    # ENCODING=b (3.0), and a data: URI in 4.0. A plain https URI is left
    # alone — People::Import::Photo explains why.
    def photo(params, value)
      raw = value.to_s.strip
      return People::Import::Photo.from_data_uri(raw) if raw.downcase.start_with?("data:")
      return unless params["ENCODING"].any? { |encoding| encoding.casecmp?("b") || encoding.casecmp?("base64") }

      People::Import::Photo.decode(raw, photo_content_type(params))
    end

    def photo_content_type(params)
      type = params["TYPE"].map(&:downcase).reject { |t| t.in?(%w[ pref ]) }.first
      return nil if type.blank?

      type = type.delete_prefix("image/")
      "image/#{type == "jpg" ? "jpeg" : type}"
    end

    def structured_name(value)
      family, given, middle, prefix, suffix = split_fields(value).map { |f| unescape(f).strip }
      [ prefix, given, middle, family, suffix ].reject(&:blank?).join(" ").presence
    end

    def structured_name_fallback(properties)
      org = properties.find { |name, _, _| name == "ORG" }
      org && split_fields(org.last).map { |f| unescape(f).strip }.reject(&:blank?).first
    end

    def formatted_address(value)
      # PO box; extended; street; locality; region; postal code; country
      split_fields(value).map { |f| unescape(f).gsub("\n", ", ").strip }.reject(&:blank?).join(", ")
    end

    MEANINGFUL_TYPES = %w[ cell mobile iphone home work main school fax pager ].freeze

    def labeled(params, value)
      types = params["TYPE"].map(&:downcase)
      label = (types & MEANINGFUL_TYPES).first
      People::Import::Labeled.new(label, value)
    end

    def assign_birthday(contact, value)
      cleaned = value.strip
      if (match = cleaned.match(/\A--(\d{2})-?(\d{2})\z/)) # year-less birthday (Apple, vCard 4)
        date = Date.new(2000, match[1].to_i, match[2].to_i)
        contact.notes = [ contact.notes, "Birthday: #{date.strftime('%B %-d')}" ].compact.join("\n")
      else
        contact.birthday = Date.iso8601(cleaned.match?(/\A\d{8}\z/) ? cleaned.gsub(/\A(\d{4})(\d{2})(\d{2})\z/, '\1-\2-\3') : cleaned)
      end
    rescue Date::Error
      nil
    end
end
