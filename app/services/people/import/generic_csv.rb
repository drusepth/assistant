# Fallback for any other CSV with recognizable headers — a hand-kept
# spreadsheet, another app's export. Fuzzy-matches columns by name; the only
# requirement is something name-like. Registered last so the branded formats
# claim their files first.
class People::Import::GenericCsv < People::Import::CsvBase
  def self.handles_headers?(headers)
    headers.any? { |h| h.match?(/\A(full ?)?name\z/i) } ||
      (headers.any? { |h| h.match?(/\Afirst ?name\z/i) } && headers.any? { |h| h.match?(/\Alast ?name\z/i) })
  end

  private
    def build_contact(row)
      People::Import::Contact.new(
        name: field(row, /\A(full ?)?name\z/i) ||
              join_present(field(row, /\Afirst ?name\z/i), field(row, /\Alast ?name\z/i)),
        relationship: field(row, /relation/i),
        phones: labeled_all(row, /phone|mobile|cell/i),
        emails: labeled_all(row, /e-?mail/i),
        addresses: labeled_all(row, /address/i, exclude: /e-?mail/i),
        birthday: parse_date(field(row, /birth|\Abday\z/i)),
        organization: field(row, /\A(company|organi[sz]ation|employer)\z/i),
        notes: field(row, /\Anotes?\z/i)
      )
    end

    def field(row, pattern)
      row.find { |key, _| key.match?(pattern) }&.last
    end

    def labeled_all(row, pattern, exclude: nil)
      row.select { |key, value| key.match?(pattern) && (exclude.nil? || !key.match?(exclude)) && value.present? }
         .map { |key, value| People::Import::Labeled.new(label_from(key), value) }
    end

    # "Work Phone" → "work"; a bare "Phone"/"Email" column gets no label.
    def label_from(key)
      label = key.sub(/\s*(phone|mobile|cell|e-?mail|address)( ?\d*)\z/i, "").strip.downcase
      label.presence
    end
end
