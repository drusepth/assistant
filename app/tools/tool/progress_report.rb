module Tool
  # The record generators (D-learning-record): portfolio, transcript, hours
  # log — assembled deterministically from the spine and study_logs, landed
  # as a Document the household owns, prints, and files. Works with no model
  # configured; a configured model adds portfolio narrative and nothing
  # else. The one tool in Education that never needs the network.
  class ProgressReport < Base
    self.title = "My learning record"
    self.description = "Portfolio, transcript, or hours log — the schooling paperwork, from your own data."
    self.section_slugs = %w[ education ]
    self.kind = :draft

    ARTIFACTS = [ "Portfolio", "Transcript", "Hours log" ].freeze
    PERIODS = [ "This school year", "This calendar year", "Everything" ].freeze

    input :artifact, kind: :select, required: true, options: ARTIFACTS,
      label: "Which record?"
    input :period, kind: :select, options: PERIODS,
      label: "Covering",
      hint: "School years start August 1st here; the file says exactly what it covers."

    def call
      record_service = Education::Record.new(
        user: user, artifact: artifact_key, since: since, profile: optional_profile
      )
      text = record_service.build

      document = record(user.documents.new(
        title: record_service.title,
        extracted_text: text,
        summary: "Generated #{artifact_key.humanize.downcase} — evidence of demonstrated work, never accreditation."
      ))
      document.file.attach(
        io: StringIO.new(text),
        filename: "#{artifact_key.dasherize}-#{Date.current.iso8601}.md",
        content_type: "text/markdown"
      )
      document.save!
      document.sections = self.class.section_records
      document
    end

    private
      def artifact_key
        inputs[:artifact].to_s.split("—").first.to_s.strip.downcase.tr(" ", "_").presence || "transcript"
      end

      def since
        case inputs[:period]
        when "This calendar year" then Date.current.beginning_of_year
        when "Everything" then nil
        else school_year_start
        end
      end

      def school_year_start
        cutoff = Date.new(Date.current.year, 8, 1)
        cutoff > Date.current ? cutoff.prev_year : cutoff
      end

      # Deliberately not `profile` (which raises): the record must build on
      # a box with no model configured — the narrative is garnish.
      def optional_profile
        candidate = user.household.model_profile
        candidate if candidate&.configured?
      end
  end
end
