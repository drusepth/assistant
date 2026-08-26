require "csv"

module Datasets
  # Household items that poison pets, shipped as data rather than recalled by
  # a model (D-pet-primitive, the D-public-datasets pattern).
  #
  # This is the one piece of pet knowledge where being right 98% of the time
  # is not good enough: the tail is a dead animal, and "is chocolate bad for
  # dogs?" is the single most-asked pet question there is. A lookup over a
  # short, stable, public-domain list answers it the same way every time, at
  # the top of the reply, before any model has spoken — and the model's job
  # shrinks to what models are good at.
  #
  # The list is deliberately short. It holds the things that actually kill
  # household pets, not everything a vet could name; a partial list that is
  # always right beats a long one that drifts.
  class PetToxics
    FILENAME = "pet_toxics.csv".freeze
    HEADERS = %w[ item species severity note aliases ].freeze

    # US Animal Poison Control, whose number is the actionable half of any
    # answer here. Code-authored, never a model's recollection of a phone
    # number.
    POISON_LINE = "ASPCA Animal Poison Control: (888) 426-4435 (US, 24/7, a fee applies). " \
      "Outside the US, call your vet or the nearest emergency clinic.".freeze

    Entry = Data.define(:item, :species, :severity, :note, :aliases) do
      def emergency? = severity == "emergency"
      def applies_to?(pet_species) = species.empty? || species.include?(pet_species)
      def terms = [ item, *aliases ]
      def label = item
    end

    def self.current = @current ||= new
    def self.reset! = @current = nil

    def initialize(path: Datasets.read_path(FILENAME))
      @entries = load(path)
    end

    attr_reader :entries

    def size = entries.size

    # Every toxin named in a stretch of text, for the pet's own species.
    # Word-boundary matching, longest term first, so "grape" doesn't fire on
    # "grapefruit juice" being ruled *out* — and so one entry can't be
    # reported twice under two of its own aliases.
    def scan(text, species: nil)
      haystack = text.to_s.downcase
      return [] if haystack.blank?

      entries.select do |entry|
        next false if species && !entry.applies_to?(species)

        entry.terms.any? { |term| haystack.match?(/(?<![a-z])#{Regexp.escape(term)}(?![a-z])/) }
      end
    end

    private
      # A missing or malformed file leaves an empty list, never an exception:
      # the guardrail failing closed would take the whole chat down, and the
      # code-authored emergency notice does not depend on it.
      def load(path)
        return [] if path.nil? || !path.exist?

        CSV.read(path, headers: true).filter_map do |row|
          item = row["item"].to_s.strip.downcase
          next if item.blank?

          Entry.new(
            item: item,
            species: row["species"].to_s.split("|").map(&:strip).reject(&:blank?),
            severity: row["severity"].to_s.strip.presence || "serious",
            note: row["note"].to_s.strip,
            aliases: row["aliases"].to_s.split("|").map { |alias_| alias_.strip.downcase }.reject(&:blank?)
          )
        end.sort_by { |entry| -entry.item.length }
      rescue CSV::MalformedCSVError, SystemCallError
        []
      end
  end
end
