module Datasets
  # What /admin says about the public datasets: what is loaded, when it last
  # arrived and from where, and — the part that used to be invisible — whether
  # the most recent attempt to get it failed.
  #
  # A refresh runs in a job, so its failure is by definition out of sight of
  # whoever pressed the button; before this, a 403 from bls.gov left the card
  # reading "not loaded" forever and the explanation eleven cards down in the
  # error log. The card now carries its own bad news.
  class Status
    DATASETS = %i[ cpi wages ].freeze

    Entry = Data.define(:key, :label, :summary, :loaded, :refreshed_at, :source, :error) do
      def loaded? = loaded
      def failed? = error.present?

      # Which attempt failed, so the card can say "import" when that is what
      # the admin actually did last.
      def failed_action = error&.source&.start_with?("dataset_import") ? "import" : "fetch"
    end

    def self.all = DATASETS.map { |key| public_send(key) }

    def self.cpi
      cpi = Cpi.current
      entry(:cpi, "CPI-U", "cpi_u.yml",
        loaded: cpi.present?,
        summary: cpi.present? ? "annual averages through #{cpi.latest_year}" : "not loaded")
    end

    def self.wages
      wages = Wages.current
      entry(:wages, "Wage medians (OES national)", Wages::META_FILENAME,
        loaded: wages.present?,
        summary: wages.present? ? "loaded (#{wages.as_of})" : "not loaded — fetch or import to light up market numbers")
    end

    def self.entry(key, label, meta_filename, loaded:, summary:)
      meta = Datasets.metadata(meta_filename)
      refreshed_at = parse_time(meta["refreshed_at"])

      Entry.new(key: key, label: label, summary: summary, loaded: loaded,
        refreshed_at: refreshed_at, source: meta["source"],
        error: last_failure(key, refreshed_at))
    end

    # Only failures newer than the data on file: a fetch that failed before a
    # successful import is history, and a card that keeps shouting about it
    # trains the admin to ignore the card.
    def self.last_failure(key, refreshed_at)
      scope = AppError.where(source: [ "dataset_refresh:#{key}", "dataset_import:#{key}" ])
      scope = scope.where(created_at: refreshed_at..) if refreshed_at
      scope.recent.first
    end

    def self.parse_time(value)
      return value if value.respond_to?(:to_time) && !value.is_a?(String)

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    private_class_method :entry, :last_failure, :parse_time
  end
end
