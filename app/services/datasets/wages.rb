require "csv"

module Datasets
  # National occupational wage medians (BLS OES/OEWS). No seed ships — the
  # table is large and revised annually — so this is empty until the admin
  # fetches or imports it (D31); consumers degrade to the placeholder
  # behavior they already had. Lookup is keyword scoring over occupation
  # titles: honest about being "closest matches", never an assertion that
  # this row is your job.
  class Wages
    FILENAME = "oews_national.csv".freeze
    META_FILENAME = "oews_national.yml".freeze

    Occupation = Data.define(:code, :title, :hourly_median, :annual_median)

    def self.current = new

    def initialize(path: Datasets.read_path(FILENAME))
      @rows = load_rows(path)
    end

    def present? = @rows.any?

    # "May 2024" style vintage recorded at fetch/import time.
    def as_of
      meta_path = Datasets.read_path(META_FILENAME)
      meta_path && YAML.safe_load(meta_path.read)["as_of"]
    end

    def search(text, limit: 3)
      terms = text.to_s.downcase.scan(/[a-z]+/).uniq - STOPWORDS
      return [] if terms.empty?

      @rows.filter_map do |row|
        title_words = row.title.downcase.scan(/[a-z]+/)
        score = terms.count { |term| title_words.any? { |word| word_match?(word, term) } }
        [ score, row ] if score.positive?
      end.sort_by { |score, row| [ -score, row.title.length ] }.first(limit).map(&:last)
    end

    # Prefix-tolerant so "warehouse" finds "Warehousing" — BLS titles decline
    # nouns freely and this must never require the user to guess the form.
    def word_match?(word, term)
      word.start_with?(term) || term.start_with?(word) ||
        (word.length >= 6 && term.length >= 6 && word[0, 6] == term[0, 6])
    end

    STOPWORDS = %w[ a an and at for in of on or the to ].freeze

    private
      def load_rows(path)
        return [] unless path

        CSV.read(path, headers: true).filter_map do |row|
          next if row["occ_title"].blank?

          Occupation.new(
            code: row["occ_code"].to_s,
            title: row["occ_title"].to_s,
            hourly_median: row["h_median"].presence&.to_f,
            annual_median: row["a_median"].presence&.to_f
          )
        end
      rescue CSV::MalformedCSVError
        []
      end
  end
end
