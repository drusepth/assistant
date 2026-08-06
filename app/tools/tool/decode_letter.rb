module Tool
  # The universal front door (D28). Any scary envelope — a denial, a
  # collection notice, a government letter — gets decoded into plain
  # language: what it is, what it's really saying, what happens if you do
  # nothing, your options. Every stated deadline lands on the calendar, and
  # the run ends by *offering* the specialized response tool with the
  # document already attached — which is how low-frequency, high-stakes
  # tools get discovered at the moment of crisis instead of in a menu.
  class DecodeLetter < Base
    self.title = "What is this letter?"
    self.description = "Any scary mail, decoded: what it really says, what happens if you ignore it, what to do."
    self.section_slugs = %w[ rights money health ]
    self.kind = :draft

    input :document_id, kind: :document, required: true,
      label: "Which document?"

    # The tools a decode may hand off to. The model proposes from this
    # catalog only; store_next_tools re-validates against it.
    ROUTABLE_SLUGS = %w[
      insurance_appeal debt_collector_response deposit_demand results_explainer dispute_letter
    ].freeze

    MAX_SECTIONS = 3

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the letter-decoding feature of a private, self-hosted life
      assistant. The user has a piece of mail that worries or confuses them — a
      bill, a denial, a collection notice, a government or legal letter. Tell
      them what it actually is and what to do about it. Respond with a JSON
      object:
      {"decoded": {"title": "...", "body": "..."},
       "sections": ["slug", ...],
       "deadlines": [{"title": "...", "date": "YYYY-MM-DD"}, ...],
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...],
       "next_tools": [{"slug": "...", "reason": "...", "inputs": {...}}, ...]}.
      The decoded body, in plain language a worried non-expert understands: what
      kind of document this is and who sent it; what it is actually saying,
      beneath the form language; what happens if the user does nothing — stated
      plainly, not alarmingly; and the user's realistic options, each in a
      sentence or two. Explain the one or two terms of art that matter. Invent
      nothing: read only what the document states, and mark real uncertainty as
      uncertainty.
      sections: where this letter belongs, chosen only from the provided list —
      at most #{MAX_SECTIONS}, ordered by relevance.
      deadlines (at most #{MAX_DEADLINES}): every date the document states or clearly implies
      by which the user must act, resolved against today's date.
      follow_ups (at most #{MAX_FOLLOW_UPS}): the immediate small actions responding implies,
      each completable in a day.
      next_tools: from the provided tool catalog only, at most #{MAX_NEXT_TOOLS}, and only when
      one clearly fits this document — a specialized tool beats the generic
      dispute letter when both apply. Give each a one-line reason in the user's
      terms. You may prefill a tool's short text inputs (an intent, a stance)
      with a suggested line via "inputs"; never guess at anything else. An empty
      list is the right answer for mail that needs no response.
    PROMPT

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        [
          "Today's date: #{Date.current.iso8601}",
          "Available sections (slug — meaning):\n#{Llm::Taxonomy.listing}",
          "Available tools (slug — what it does):\n#{tool_catalog}",
          "The document (titled “#{document.title}”):\n#{document_text(document)}"
        ].join("\n\n")
      end

      def tool_catalog
        ROUTABLE_SLUGS.map do |slug|
          tool = Tool.find!(slug)
          input_names = tool.inputs.map { |input| "#{input.name}#{" (required)" if input.required?}" }
          "#{slug} — #{tool.description} Inputs: #{input_names.join(", ")}."
        end.join("\n")
      end

      def document = chosen_document

      # Triage includes filing: the decoded note lands in the document's own
      # sections plus wherever the model just classified the letter. The
      # three sections this tool registers on are a discovery surface, not a
      # filing claim — a decoded EOB belongs in Health, not everywhere.
      def filing
        @filing ||= (document.sections.to_a + @model_sections.to_a).uniq
      end

      def handle(response)
        body = response.dig("decoded", "body")
        raise Llm::Error, "The model couldn't decode that document — try again." if body.blank?

        @model_sections = Llm::Taxonomy.match(response["sections"], limit: MAX_SECTIONS)

        create_note(
          title: response.dig("decoded", "title").presence || "Decoded — #{document.title}",
          body: body
        )
        create_follow_ups(response["follow_ups"])
        create_deadline_events(response["deadlines"])
        store_next_tools(with_document(response["next_tools"]), allowed: ROUTABLE_SLUGS)
      end

      # The model proposes which tool; code attaches which document — model
      # output never carries database ids.
      def with_document(proposals)
        Array(proposals).map do |proposal|
          next proposal unless proposal.is_a?(Hash)

          inputs = proposal["inputs"].is_a?(Hash) ? proposal["inputs"] : {}
          proposal.merge("inputs" => inputs.merge("document_id" => document.id.to_s))
        end
      end
  end
end
