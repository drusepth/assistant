module Tool
  # Walk into an appointment with everything in one place: the questions
  # worth asking and a one-page history pulled from the user's own Health
  # items. Preparation and comprehension, never diagnosis (PRODUCT.md's
  # Health scoping). Reads the user's own data only — a shared spouse's
  # appointment is not your history.
  class DoctorVisitPrep < Base
    self.title = "Prep for a doctor visit"
    self.description = "A question list and one-page history summary to bring to your appointment."
    self.section_slugs = %w[ health ]
    self.kind = :draft

    input :reason,
      label: "What's the visit about?",
      hint: "Optional — “annual physical”, “knee pain follow-up”."

    LOOKBACK = 24.months
    MAX_ITEMS = 10

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the doctor-visit prep feature of a private, self-hosted life
      assistant. From the user's own health records below, the draft is a prep
      sheet they can bring to an appointment, with three parts: questions worth
      asking the doctor; a brief history summary (symptoms, visits, medications
      mentioned — organized, in plain language); and anything from the records
      the doctor should probably see. When the records list allergies, repeat
      them verbatim near the top of the sheet — never edit, soften, or omit
      one. You prepare and organize — you NEVER diagnose, speculate about
      conditions, or recommend treatment; questions are for the doctor to
      answer.
      follow_ups are practical (gather a missing record, book the slot).
      #{DRAFT_FORMAT}
    PROMPT

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "What the visit is about: #{inputs[:reason]}" if inputs[:reason].present?
        parts << listing("Health events (past two years and upcoming)",
          health(user.events.where(starts_at: LOOKBACK.ago..)).order(:starts_at)) { |e| "#{e.starts_at.to_date.iso8601} — #{e.title}" }
        parts << listing("Open health tasks", health(user.tasks.open), &:title)
        # Allergies lead, as their own block rather than three lines buried in
        # the notes dump — "any allergies?" is the first question in the room,
        # and severity is what changes the answer to it. Unlike the rest, this
        # block ignores section tags: an allergy is one whether or not the note
        # ever got filed under Health, and the sheet can't afford to miss it.
        parts << listing("Allergies (worst first)", user.notes.allergies.by_severity.limit(MAX_ITEMS)) do |n|
          [ n.title, n.severity && "#{n.severity} reaction", (n.body unless n.body == n.title) ].compact.join(" — ")
        end
        parts << listing("Health notes", health(user.notes.except_allergies).order(updated_at: :desc)) { |n| [ n.title, n.body.truncate(500) ].compact.join(": ") }
        parts << listing("Health documents", health(user.documents)) { |d| [ d.title, d.summary&.truncate(300) ].compact.join(" — ") }
        parts.compact.join("\n\n")
      end

      def health(scope)
        scope.in_section(health_section_ids).limit(MAX_ITEMS)
      end

      def health_section_ids
        @health_section_ids ||= begin
          section = Section.find_by(slug: "health")
          section ? [ section.id, *section.children.ids ] : []
        end
      end

      def listing(label, records)
        rows = records.map { |record| "- #{yield(record)}" }
        rows.any? ? "#{label}:\n#{rows.join("\n")}" : nil
      end

      def fallback_title = "Doctor-visit prep sheet"
  end
end
