module Documents
  # The Milestone-1 AI feature: extract a document's text, then ask the
  # household's configured model for a plain-language summary and suggested
  # section tags. Suggestions are only ever suggestions (trust ladder, D6) —
  # applying them is a human click on the document page.
  class Analyze
    class UnsupportedFileType < StandardError; end

    EXTRACTABLE_TEXT_TYPES = %w[ text/plain text/markdown text/csv application/json ].freeze
    PROMPT_TEXT_LIMIT = 12_000
    STORED_TEXT_LIMIT = 20_000
    MAX_SUGGESTIONS = 3

    Result = Data.define(:summary, :section_slugs, :extracted_text)

    def initialize(document:, profile:)
      @document = document
      @profile = profile
    end

    def call
      text = extract_text
      response = @profile.client.chat(messages(text), json: true)

      Result.new(
        summary: response["summary"].to_s.strip,
        section_slugs: valid_slugs(response["sections"]),
        extracted_text: text&.truncate(STORED_TEXT_LIMIT)
      )
    end

    private
      def extract_text
        return nil unless @document.file.attached?

        content_type = @document.file.content_type
        if content_type == "application/pdf"
          extract_pdf
        elsif EXTRACTABLE_TEXT_TYPES.include?(content_type) || content_type.start_with?("text/")
          @document.file.download.force_encoding(Encoding::UTF_8).scrub
        else
          raise UnsupportedFileType,
            "Text can't be extracted from #{content_type} files yet — PDF and plain-text files are supported."
        end
      end

      def extract_pdf
        @document.file.open do |io|
          PDF::Reader.new(io).pages.map(&:text).join("\n").scrub
        end
      rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
        raise UnsupportedFileType, "This PDF couldn't be read: #{e.message}"
      end

      def messages(text)
        [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt(text) }
        ]
      end

      def system_prompt
        <<~PROMPT
          You are the document-understanding feature of a private, self-hosted life assistant.
          Summarize documents in plain, jargon-free language for someone without professional
          advisors, and suggest which life sections the document belongs to.
          Respond with a JSON object: {"summary": "...", "sections": ["slug", ...]}.
          The summary is 2-4 sentences; mention any deadlines, amounts, or required actions.
          Choose at most #{MAX_SUGGESTIONS} sections, only from the provided list, ordered by relevance.
        PROMPT
      end

      def user_prompt(text)
        parts = [ "Title: #{@document.title}" ]
        parts << "Description: #{@document.description}" if @document.description.present?
        parts << "Available sections (slug — meaning):\n#{taxonomy}"
        parts << (text.present? ? "Document text:\n#{text.truncate(PROMPT_TEXT_LIMIT)}" : "No file text is available — use the title and description.")
        parts.join("\n\n")
      end

      def taxonomy
        Section.order(:parent_id, :position).map { |section| "#{section.slug} — #{section.qualified_name}" }.join("\n")
      end

      def valid_slugs(slugs)
        known = Section.where(slug: Array(slugs).map(&:to_s)).pluck(:slug)
        Array(slugs).map(&:to_s).select { |slug| known.include?(slug) }.first(MAX_SUGGESTIONS)
      end
  end
end
