module Documents
  # The Milestone-1 AI feature: read a document, then ask the household's
  # configured model for a plain-language summary, suggested section tags,
  # and — since D-document-intake — what in it belongs somewhere else in
  # the household's records, as landings validated against the registry.
  # Suggestions are only ever suggestions (trust ladder, D6): sections are
  # applied by a click on the document page, landings by Save on the review
  # page.
  #
  # Reading is Documents::Read's job (INTAKE_PLAN W1): text and text-bearing
  # PDFs arrive as text, images and scans as page images for a vision model.
  # When the model is shown images it is also asked for a transcription,
  # which is stored as the document's text so search and the tools that read
  # a document's text (decode_letter, results_explainer) work on a photo of
  # a letter exactly as on a PDF of one.
  #
  # One call, normally. When the registry's generated block outgrows a small
  # model's window (`schema_budget`), the call splits (INTAKE_PLAN §3): a
  # presence pass names which kinds the document contains, and a detail pass
  # carries only those kinds' fields — asking about less, never swapping in
  # a cheaper mechanism (D-no-keyword-logic).
  class Analyze
    PROMPT_TEXT_LIMIT = 12_000
    STORED_TEXT_LIMIT = 20_000
    MAX_SUGGESTIONS = 3
    TITLE_LIMIT = 120

    # Characters of registry block above which the call splits in two. Room
    # for the whole registry and a household's listings in one pass on any
    # model with a real window; a class attribute so a test can lower it.
    class_attribute :schema_budget, default: 8_000

    # Tools the reader may point a document at (D28, on a document instead
    # of a run): each takes the document as its input. A slug outside this
    # list is dropped, so a retired tool can never break the page.
    NEXT_TOOLS = %w[ decode_letter results_explainer insurance_explainer decode_vet_estimate
                     check_pay_stub decode_offer debt_collector_response ].freeze

    Result = Data.define(:summary, :section_slugs, :extracted_text, :facts, :landings, :title)

    # Career-aware extraction (D-career-signal, docs/CAREER.md §1): the fields kept from
    # a pay-stub read. Code whitelists, so the stored JSON never grows keys
    # the consumers don't know.
    PAY_STUB_FIELDS = %w[ employer pay_date period_start period_end rate hours overtime_hours gross net ].freeze
    MAX_DEDUCTIONS = 12

    def initialize(document:, profile:)
      @document = document
      @profile = profile
      @context = Landing::Context.new(user: document.user, document: document)
    end

    def call
      content = Read.new(@document, vision: @profile.vision?).call
      block = Landing.prompt_block(@context)

      if block.length <= schema_budget
        response = chat(content, landings: block)
        landings = response["landings"]
      else
        response = chat(content, landings: nil)
        present = Landing.present_kinds(response["present_kinds"])
        landings = present.any? ? chat(content, landings: Landing.prompt_block(@context, kinds: present), detail: true)["landings"] : []
      end

      Result.new(
        summary: response["summary"].to_s.strip,
        section_slugs: valid_slugs(response["sections"]),
        extracted_text: stored_text(content, response),
        facts: extracted_facts(response),
        landings: Landing.propose(landings, @context),
        title: response["title"].to_s.squish.truncate(TITLE_LIMIT).presence
      )
    end

    private
      def chat(content, landings:, detail: false)
        @profile.client.chat(messages(content, landings: landings, detail: detail), json: true)
      end

      def messages(content, landings:, detail:)
        [
          { role: "system", content: detail ? detail_prompt(content, landings) : system_prompt(content, landings) },
          { role: "user", content: user_content(content) }
        ]
      end

      # `landings` is the registry block for a single pass, or nil for the
      # presence pass, which asks for kind names instead.
      def system_prompt(content, landings)
        <<~PROMPT
          You are the document-understanding feature of a private, self-hosted life assistant.
          Summarize documents in plain, jargon-free language for someone without professional
          advisors, suggest which life sections the document belongs to, and list what in the
          document belongs somewhere else in the household's records.
          Respond with a JSON object: {"summary": "...", "title": "...", "sections": ["slug", ...],
          "health_plan": true or false, "next_tool": {"slug": "...", "reason": "..."} or null,
          #{landings ? '"landings": [{"kind": "...", ...}, ...]' : '"present_kinds": ["kind", ...]'}#{', "text": "..."' if content.images?}}.
          The summary is 2-4 sentences; mention any deadlines, amounts, or required actions.
          The title is a short, specific name for the document (at most 8 words), e.g.
          "Rex — vet discharge sheet, 12 Aug 2026".
          Choose at most #{MAX_SUGGESTIONS} sections, only from the provided list, ordered by relevance.
          "health_plan" is true only when the document is itself a health insurance plan document —
          an insurance card, a summary of benefits, an explanation of benefits, a policy — for a
          person or a pet; a bill, a claim form or a letter mentioning insurance is false.
          "next_tool" names one tool from the list below that would help the reader with this
          document, with a one-line reason, or null when none fits:
          #{next_tools_listing}
          #{transcription_instruction if content.images?}

          #{landings || Landing.names_block}

          If — and only if — the document is a pay stub or paycheck record, also include
          "pay_stub": {"employer": "...", "pay_date": "YYYY-MM-DD", "period_start": "YYYY-MM-DD",
          "period_end": "YYYY-MM-DD", "rate": "hourly pay rate", "hours": "...", "overtime_hours": "...",
          "gross": "...", "net": "...", "deductions": [{"label": "...", "amount": "..."}, ...]}.
          Copy numbers exactly as printed and omit any field the stub doesn't state;
          for any other kind of document, omit "pay_stub" entirely.
        PROMPT
      end

      # The detail pass: only the landings, only the present kinds.
      def detail_prompt(content, landings)
        <<~PROMPT
          You are the document-understanding feature of a private, self-hosted life assistant.
          Read the document and list what in it belongs in the household's records.
          Respond with a JSON object: {"landings": [{"kind": "...", ...}, ...]}.
          #{"The document arrives as page images." if content.images?}

          #{landings}
        PROMPT
      end

      def next_tools_listing
        NEXT_TOOLS.filter_map { |slug| Tool.find(slug) }
          .map { |tool| "#{tool.slug} — #{tool.title}: #{tool.description}" }.join("\n")
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
        parts = [ "Today's date: #{Date.current.iso8601}", "Title: #{@document.title}" ]
        parts << "Description: #{@document.description}" if @document.description.present?
        # Where the document was filed is what it is *about* — "Filed about:
        # Rex" is how a discharge sheet's landings know whose they are.
        if (filed = @context.filing).any?
          parts << "Filed under: #{filed.map(&:qualified_name).join(", ")}"
        end
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
        # Whether the document *is* a policy (D-document-intake): the
        # reader's verdict, kept apart from the owner's own answer in
        # `documents.health_plan` so a re-read can change its mind and the
        # page can say whose answer it shows (Health::Coverage.verdict). A
        # reader that didn't answer leaves no verdict rather than a "no".
        facts = {}
        facts["health_plan"] = response["health_plan"] if [ true, false ].include?(response["health_plan"])
        if (tool = next_tool(response["next_tool"]))
          facts["next_tool"] = tool
        end
        facts.merge(pay_stub_facts(response["pay_stub"]))
      end

      # The tool the reader pointed at, validated against the allowed list
      # and stored as {slug, reason} — the D28 sanitization, for documents.
      def next_tool(proposal)
        return nil unless proposal.is_a?(Hash)

        slug = proposal["slug"].to_s
        return nil unless NEXT_TOOLS.include?(slug) && Tool.find(slug)

        { "slug" => slug, "reason" => proposal["reason"].to_s.squish.truncate(200).presence }.compact
      end

      def pay_stub_facts(stub)
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
