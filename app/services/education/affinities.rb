module Education
  # The static half of subject suggestion (docs/EDUCATION_PLAN.md §7):
  # hobby-lens name → subject worth learning, with the reason spelled out.
  # Deterministic and auditable — the common cases never cost a model call.
  class Affinities
    Entry = Data.define(:matchers, :subject, :reason)

    PATH = Rails.root.join("db/education_affinities.yml")

    class << self
      def all
        @all ||= YAML.safe_load_file(PATH).map do |row|
          Entry.new(
            matchers: Array(row["match"]).map { |m| m.to_s.downcase },
            subject: row.fetch("subject"),
            reason: row["reason"].to_s
          )
        end
      end

      # First entry whose matcher appears in the lens name, or nil — the
      # model extension picks up the lenses this map doesn't know.
      def for(lens_name)
        name = lens_name.to_s.downcase
        all.find { |entry| entry.matchers.any? { |matcher| name.include?(matcher) } }
      end

      def reset! = @all = nil
    end
  end
end
