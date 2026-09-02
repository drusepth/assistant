module Documents
  # The Milestone-1 AI feature: read a document, then ask the household's
  # configured model for a plain-language summary and suggested section
  # tags. Suggestions are only ever suggestions (trust ladder, D6) —
  # applying them is a human click on the document page.
  #
  # Reading is Documents::Read's job (INTAKE_PLAN W1): text and text-bearing
  # PDFs arrive as text, images and scans as page images for a vision model.
  # When the model is shown images it is also asked for a transcription,
  # which is stored as the document's text so search and the tools that read
  # a document's text (decode_letter, results_explainer) work on a photo of
  # a letter exactly as on a PDF of one.
  class Analyze
    PROMPT_TEXT_LIMIT = 12_000
    STORED_TEXT_LIMIT = 20_000
    MAX_SUGGESTIONS = 3

    Result = Data.define(:summary, :section_slugs, :extracted_text, :facts)

    # Career-aware extraction (D-career-signal, docs/CAREER.md §1): the fields kept from
    # a pay-stub read. Code whitelists, so the stored JSON never grows keys
    # the consumers don't know.
    PAY_STUB_FIELDS = %w[ employer pay_date period_start period_end rate hours overtime_hours gross net ].freeze
    MAX_DEDUCTIONS = 12

    def initialize(document:, profile:)
      @document = document
      @profile = profile
    end

    def call
      content = Read.new(@document, vision: @profile.vision?).call
      response = @profile.client.chat(messages(content), json: true)

      Result.new(
        summary: response["summary"].to_s.strip,
        section_slugs: valid_slugs(response["sections"]),
        extracted_text: stored_text(content, response),
        facts: extracted_facts(response)
      )
    end

    private
      def messages(content)
        [
          { role: "system", content: system_prompt(content) },
          { role: "user", content: user_content(content) }
        ]
      end

      def system_prompt(content)
        <<~PROMPT
          You are the document-understanding feature of a private, self-hosted life assistant.
          Summarize documents in plain, jargon-free language for someone without professional
          advisors, and suggest which life sections the document belongs to.
          Respond with a JSON object: {"summary": "...", "sections": ["slug", ...]#{', "text": "..."' if content.images?}}.
          The summary is 2-4 sentences; mention any deadlines, amounts, or required actions.
          Choose at most #{MAX_SUGGESTIONS} sections, only from the provided list, ordered by relevance.
          #{transcription_instruction if content.images?}
          If — and only if — the document is a pay stub or paycheck record, also include
          "pay_stub": {"employer": "...", "pay_date": "YYYY-MM-DD", "period_start": "YYYY-MM-DD",
          "period_end": "YYYY-MM-DD", "rate": "hourly pay rate", "hours": "...", "overtime_hours": "...",
          "gross": "...", "net": "...", "deductions": [{"label": "...", "amount": "..."}, ...]}.
          Copy numbers exactly as printed and omit any field the stub doesn't state;
          for any other kind of document, omit "pay_stub" entirely.
        PROMPT
      end

      def transcription_instruction
        "The document arrives as one or more page images. \"text\" is a faithful transcription of " \
        "everything printed or written on them, in reading order, as printed — never summarized, " \
        "never corrected, never filled in where the image is unreadable (write [unreadable] there)."
      end

      # A text read is one string; an image read is the OpenAI multi-part
      # shape — the text prompt, then one image_url part per page.
      def user_content(content)
        return user_prompt(content.text) unless content.images?

        [ { type: "text", text: user_prompt(nil) } ] +
          content.images.map { |url| { type: "image_url", image_url: { url: url } } }
      end

      def user_prompt(text)
        parts = [ "Title: #{@document.title}" ]
        parts << "Description: #{@document.description}" if @document.description.present?
        parts << "Available sections (slug — meaning):\n#{taxonomy}"
        parts << if text.present?
          "Document text:\n#{text.truncate(PROMPT_TEXT_LIMIT)}"
        elsif @document.file.attached?
          "The document's pages follow as images."
        else
          "No file text is available — use the title and description."
        end
        parts.join("\n\n")
      end

      def stored_text(content, response)
        text = content.images? ? response["text"].to_s.strip.presence : content.text
        text&.truncate(STORED_TEXT_LIMIT)
      end

      def taxonomy
        Section.order(:parent_id, :position).map { |section| "#{section.slug} — #{section.qualified_name}" }.join("\n")
      end

      def valid_slugs(slugs)
        known = Section.where(slug: Array(slugs).map(&:to_s)).pluck(:slug)
        Array(slugs).map(&:to_s).select { |slug| known.include?(slug) }.first(MAX_SUGGESTIONS)
      end

      def extracted_facts(response)
        stub = response["pay_stub"]
        return {} unless stub.is_a?(Hash)

        kept = stub.slice(*PAY_STUB_FIELDS)
          .transform_values { |value| value.to_s.strip }
          .reject { |_field, value| value.blank? }
        deductions = Array(stub["deductions"]).first(MAX_DEDUCTIONS).filter_map do |deduction|
          next unless deduction.is_a?(Hash) && deduction["label"].present?

          { "label" => deduction["label"].to_s.strip, "amount" => deduction["amount"].to_s.strip }
        end
        kept["deductions"] = deductions if deductions.any?
        kept.present? ? { "pay_stub" => kept } : {}
      end
  end
end
