module Tool
  # The highest-frequency high-stakes Career moment (docs/CAREER.md §3.1).
  # Reads the job listing (pasted or from the vault) against the user's own
  # record — resume, work-history note, win log — and lands a prep sheet
  # that maps *their* logged wins onto each requirement as tellable stories.
  # Tier-A honesty: the model knows interviewing evergreen-well but not this
  # week's news about the company, so company facts become a research
  # checklist, never inventions. Routes onward to the mock interview (D28).
  class InterviewPrep < Base
    self.title = "Prep me for an interview"
    self.description = "The listing decoded, your wins mapped to their asks, the likely questions — and what to look up."
    self.section_slugs = %w[ career ]
    self.kind = :draft

    input :role, required: true,
      label: "What's the job?",
      hint: "“Warehouse shift lead at Acme”, “junior developer, remote”."
    input :listing, kind: :textarea,
      label: "Paste the job listing",
      hint: "Optional if you pick it from your documents below."
    input :document_id, kind: :document,
      label: "…or the listing from your documents"
    input :concerns,
      label: "What worries you?",
      hint: "Optional — “the gap in my resume”, “panel interviews freak me out”."

    MAX_FOLLOW_UPS = 2
    MAX_RESEARCH = 6
    ROUTABLE_SLUGS = %w[ mock_interview ].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the interview-prep feature of a private, self-hosted life
      assistant. The user has an interview coming; the interviewer does this
      every week. Even the odds. Respond with a JSON object:
      {"prep": {"title": "...", "body": "..."},
       "research": ["...", ...],
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The prep body is a one-page sheet, plain jargon-free language:
      - What this role actually wants, translated from the listing's language
        (or from the role line alone when no listing is given).
      - Their asks, your answers: for each main requirement, which of the
        user's tracked wins or experience answers it — phrased as a short
        tellable story ("when X happened, I did Y, and Z"). Use only what the
        user's data states; where their record shows nothing for an ask, say
        so honestly and suggest the nearest true story, never an invented one.
      - The questions they'll likely ask, the trap ones flagged with what the
        trap is ("tell me about a conflict" is not about the conflict).
      - Three smart questions for the user to ask them.
      - A short logistics checklist (what to bring, what to confirm).
      If the user named a worry, address it directly with a concrete plan.
      research: at most #{MAX_RESEARCH} specific things to look up about the company or
      role before the interview — you know interviewing, not this company's
      current facts, so name what to check rather than asserting it.
      follow_ups: at most #{MAX_FOLLOW_UPS}, each doable in a day.
    PROMPT

    def call
      if inputs[:listing].blank? && chosen_document.nil?
        raise Llm::Error, "Paste the listing text or pick it from your documents — either works."
      end
      super
    end

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "The job: #{inputs[:role]}"
        parts << "What worries the user: #{inputs[:concerns]}" if inputs[:concerns].present?
        parts << "The job listing:\n#{inputs[:listing]}" if inputs[:listing].present?
        if (document = chosen_document)
          parts << "The job listing (from the document “#{document.title}”):\n#{document_text(document)}"
        end
        context = section_context
        unless context.empty?
          parts << "The user's tracked career record — wins, work history, resume:\n#{context.to_prompt}"
        end
        parts.join("\n\n")
      end

      def filing_sources = [ chosen_document ]

      def handle(response)
        body = response.dig("prep", "body")
        raise Llm::Error, "The model didn't return a prep sheet — try again." if body.blank?

        research = bulleted_block("Before the interview, look up", response["research"], limit: MAX_RESEARCH)
        create_note(
          title: response.dig("prep", "title").presence || "Interview prep — #{inputs[:role]}",
          body: [ body, research ].compact.join("\n\n")
        )
        create_follow_ups(response["follow_ups"], limit: MAX_FOLLOW_UPS)
        store_next_tools(
          [ { "slug" => "mock_interview",
              "inputs" => { "focus" => inputs[:role].to_s },
              "reason" => "Rehearse it out loud — the prep sheet is the study guide, the mock is the practice test." } ],
          allowed: ROUTABLE_SLUGS
        )
      end
  end
end
