module Tool
  # The application kit (docs/CAREER.md §3.2): the user's actual history
  # mapped onto this listing's language — tailored bullets, a cover-letter
  # draft, and an honest account of the gaps. The hard rule is the one
  # appended by code below: an assistant that lies on your resume is a
  # liability sold as a friend, so unsupported qualifications become
  # placeholders, never claims. Routes onward to interview prep (D28).
  class TailorApplication < Base
    self.title = "Tailor my application"
    self.description = "Your real history, rewritten in this listing's language — bullets, cover letter, and the honest gaps."
    self.section_slugs = %w[ career ]
    self.kind = :draft

    input :role, required: true,
      label: "What's the job?",
      hint: "“Warehouse shift lead at Acme”."
    input :listing, kind: :textarea,
      label: "Paste the job listing",
      hint: "Optional if you give a link or pick a document below."
    input :listing_url,
      label: "…or a link to the listing",
      hint: "The app fetches the page itself — works with any model."
    input :listing_document_id, kind: :document,
      label: "…or the listing from your documents"
    input :resume_document_id, kind: :document,
      label: "Your current resume, if it's in your documents",
      hint: "No resume yet? Your logged wins and work-history note carry it."

    MAX_FOLLOW_UPS = 2
    ROUTABLE_SLUGS = %w[ interview_prep ].freeze

    # Appended by code, not the model — the never-fabricate guardrail must
    # not depend on sampling.
    HONESTY_FOOTER =
      "Check every line against your real history before sending — nothing in a draft " \
      "should claim experience, titles, dates, or credentials you don't have. " \
      "[BRACKETED PLACEHOLDERS] mark what only you can fill in.".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the application-tailoring feature of a private, self-hosted life
      assistant. The user is applying for a job; your work is translation, not
      invention — their real history, said in this listing's language. Respond
      with a JSON object:
      {"tailored": {"title": "...", "body": "..."},
       "cover_letter": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The tailored body has three parts:
      - Resume bullets, rewritten: the user's actual experience and logged
        wins phrased in the listing's own vocabulary, concrete and specific.
        Use ONLY what their data states — never invent experience, employers,
        titles, dates, tools, or credentials. Where the listing asks for
        something their record doesn't show, do not manufacture it.
      - The honest gaps: which stated requirements their record doesn't
        cover, and for each the evergreen advice — address it in the cover
        letter, reframe adjacent experience truthfully, or apply anyway
        (most postings are wish lists).
      - What to emphasize: the two or three strongest true matches.
      The cover_letter is a short, send-ready draft in plain human language —
      no template filler — leading with the strongest true match, addressing
      the most important gap honestly, with [BRACKETED PLACEHOLDERS] for
      anything unknown (hiring manager's name, company specifics).
      follow_ups: at most #{MAX_FOLLOW_UPS}, each doable in a day.
    PROMPT

    def call
      if inputs[:listing].blank? && inputs[:listing_url].blank? && chosen_document(:listing_document_id).nil?
        raise Llm::Error, "Paste the listing text, give a link, or pick it from your documents — any works."
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
        parts << "The job listing:\n#{inputs[:listing]}" if inputs[:listing].present?
        if (page = fetched_page)
          parts << "The job listing (fetched from #{page.final_url}):\n#{page.text.truncate(MAX_DOCUMENT_CHARS)}"
        end
        if (listing = chosen_document(:listing_document_id))
          parts << "The job listing (from the document “#{listing.title}”):\n#{document_text(listing)}"
        end
        if (resume = chosen_document(:resume_document_id))
          parts << "The user's current resume (“#{resume.title}”):\n#{document_text(resume)}"
        end
        context = section_context
        unless context.empty?
          parts << "The user's tracked career record — wins, work history:\n#{context.to_prompt}"
        end
        parts.join("\n\n")
      end

      def filing_sources = [ chosen_document(:listing_document_id), chosen_document(:resume_document_id) ]

      def handle(response)
        body = response.dig("tailored", "body")
        raise Llm::Error, "The model didn't return the tailored draft — try again." if body.blank?

        create_note(
          title: response.dig("tailored", "title").presence || "Application draft — #{inputs[:role]}",
          body: [ body, HONESTY_FOOTER ].join("\n\n")
        )
        if (cover = response.dig("cover_letter", "body")).present?
          create_note(
            title: response.dig("cover_letter", "title").presence || "Cover letter — #{inputs[:role]}",
            body: [ cover, HONESTY_FOOTER ].join("\n\n")
          )
        end
        create_follow_ups(response["follow_ups"], limit: MAX_FOLLOW_UPS)
        store_next_tools(
          [ { "slug" => "interview_prep",
              "inputs" => { "role" => inputs[:role].to_s },
              "reason" => "Application out the door — the interview is the next door." } ],
          allowed: ROUTABLE_SLUGS
        )
      end
  end
end
