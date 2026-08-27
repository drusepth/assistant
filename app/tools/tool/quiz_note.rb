module Tool
  # "Quiz me on this" on a note (D-note-quiz). The Education hub's retrieval
  # gate — asking beats rereading — pointed at the other place the user keeps
  # things worth knowing: their notes. Sectionless and bound to its note
  # through `tool_runs.subject` rather than a form input, the way a task's
  # conversation is (D30): the entry point is the note page, one click, no
  # picker.
  #
  # Two flavors, decided by where the note came from:
  #
  #   a plain note  — the quiz is on what the note says.
  #   a quiz recap  — a note a quiz filed is a report card, not material, so
  #                   quizzing its prose would ask "how did you do?" back at
  #                   you. A recap points past itself: at the cards its quiz
  #                   minted from the misses, at the note the quiz was taken
  #                   on, and at the topic when the chain started in the
  #                   syllabus. Finishing one of those feeds the same loop
  #                   the Education quiz does — mastery on evidence, fresh
  #                   cards for what's still missing, a study_log line.
  class QuizNote < ChatBase
    self.title = "Quiz me on this"
    self.description = "A short retrieval check on one note — what's in it, asked back at you."
    self.section_slugs = []
    self.quick_replies = [
      "Hint, please",
      "I don't know — show me",
      "Next question"
    ]

    MAX_NOTE_CHARS = 8_000
    MAX_RECAP_CHARS = 2_000
    MAX_CARDS = 10
    # The runs whose notes are report cards rather than material.
    QUIZ_SLUGS = %w[ quiz_me quiz_note ].freeze
    # A recap of a recap of a recap is as far back as anyone needs; the cap
    # is what keeps a chain from growing the prompt without limit.
    MAX_WALK = 3

    def self.recap_button_label(_run) = "Finish & save the result"

    def self.recap_pending_label = "Grading…"

    def self.recap_hint
      "Finishing grades the quiz and files a short recap — what stuck, and what to reread."
    end

    BEHAVIOR = <<~PROMPT.freeze
      You are the quiz feature of a private, self-hosted life assistant. Run a
      short retrieval check on one thing the user wrote down — recall causes
      learning, so the asking is the point.
      Rules of the room:
      - One question at a time, 4 to 6 questions total, then say the quiz is done
        and they can finish to save the result.
      - Ask only about the material below. Never quiz trivia around it, and
        never invent facts it doesn't contain.
      - No teaching before an attempt: after they answer, say what was right, give
        the correct answer if they missed, one line of why, then move on.
      - "I don't know" is a fine answer and scores as a miss without ceremony.
      - Plain conversational text, no markdown tables, no LaTeX. Warm, brisk, honest.
    PROMPT

    def call
      note
      super
    end

    def recap!
      response = profile.client.chat(recap_messages, json: true)
      body = response.dig("recap", "body")
      raise Llm::Error, "The model couldn't grade the quiz — try again." if body.blank?

      # A quiz that traces to the syllabus is evidence there like any other:
      # forward-only mastery, the misses back into the FSRS queue, and the
      # durable hours line. A quiz on an ordinary note has no ladder to move.
      if (topic = study_topic)
        apply_mark(topic, response.dig("verdict", "state").to_s, evidence: "quiz")
        mint_review_items(topic, response["missed"])
        log_study_session(subject: topic.subject, topic: topic, activity: :review)
      end
      create_note(title: response.dig("recap", "title").presence || recap_fallback_title, body: body)
    end

    private
      include EducationSupport

      # Through the visibility wall like every owned item a tool reads: a
      # note shared with you is one you can be quizzed on, and one that has
      # since vanished fails the run rather than quizzing you on nothing.
      def note
        @note ||= (run.subject.is_a?(Note) ? Note.visible_to(user).find_by(id: run.subject_id) : nil) ||
          raise(Llm::Error, "That note is gone or no longer shared with you.")
      end

      # ── Where the note came from ───────────────────────────────────────

      # The quiz run that filed this note, when a quiz did. Its review items
      # are the freshest misses — what a second pass should open with.
      def origin_run
        return @origin_run if defined?(@origin_run)

        run = note.source_run
        @origin_run = run if run && QUIZ_SLUGS.include?(run.tool_slug)
      end

      # Walking back up the chain of recaps to what the quizzing was about:
      # the topic if it started in the syllabus, otherwise the note the
      # material actually lives in. Both nil for an ordinary note, which is
      # the common case and costs one query.
      def chain
        @chain ||= begin
          material = topic = nil
          current = note

          MAX_WALK.times do
            filed_by = current.source_run
            break unless filed_by && QUIZ_SLUGS.include?(filed_by.tool_slug)

            # A chain that reaches the syllabus ends there: the topic is the
            # material, and the note we walked through is another report card.
            if (topic = owned_topic(filed_by.inputs["topic_id"]))
              material = nil
              break
            end

            earlier = filed_by.subject
            break unless earlier.is_a?(Note) && earlier.visible_to?(user)

            material = current = earlier
          end

          { material: material, topic: topic }
        end
      end

      def study_topic = chain[:topic]
      def material_note = chain[:material]

      def owned_topic(id)
        Topic.joins(:subject).where(subjects: { user_id: user.id }).find_by(id: id) if id.present?
      end

      def missed_cards
        @missed_cards ||= Array(origin_run&.items).grep(ReviewItem).first(MAX_CARDS)
      end

      # A recap only earns the second-pass treatment if walking back found
      # something to ask about. When it didn't — the topic was deleted, the
      # cards are gone — the recap is all there is, so quiz it plainly
      # rather than sending a prompt with no material in it.
      def re_quiz? = study_topic || material_note || missed_cards.any?

      # ── The prompt ─────────────────────────────────────────────────────

      def system_prompt
        [ BEHAVIOR, material ].join("\n\n")
      end

      def material
        return note_block(note) unless origin_run && re_quiz?

        [
          (topic_context(study_topic) if study_topic),
          (note_block(material_note, heading: "The material the last quiz was on") if material_note),
          missed_block,
          "The recap of that quiz (context, not material — never quiz its prose):\n#{note.body.truncate(MAX_RECAP_CHARS)}"
        ].compact.join("\n\n")
      end

      def note_block(subject, heading: "The note to quiz them on")
        title = subject.title.presence
        [ "#{heading}#{" — “#{title}”" if title}:", subject.body.truncate(MAX_NOTE_CHARS) ].join("\n")
      end

      def missed_block
        return nil if missed_cards.none?

        lines = missed_cards.map { |card| "- #{card.prompt}#{" → #{card.answer}" if card.answer.present?}" }
        "What they missed last time — start here, and ask these in your own words rather than reading them back:\n#{lines.join("\n")}"
      end

      def opening_instruction
        if origin_run && re_quiz?
          "Open the quiz: one sentence saying this is a second pass at what they missed and how many questions, then question 1."
        else
          "Open the quiz: one sentence naming what the note is about and how many questions, then question 1."
        end
      end

      def recap_instruction
        study_topic ? graded_recap_instruction : plain_recap_instruction
      end

      def plain_recap_instruction
        <<~TEXT
          The quiz is over. Respond with a JSON object:
          {"recap": {"title": "Quiz — <what it was about>", "body": "..."}}.
          The body: how it went, what they have cold and what to reread — short,
          written for them to reread later. Judge only questions actually
          attempted; an abandoned quiz with no answers says so plainly.
        TEXT
      end

      def graded_recap_instruction
        <<~TEXT
          The quiz is over. Respond with a JSON object:
          {"recap": {"title": "Quiz — <topic>", "body": "..."},
           "verdict": {"state": "learning" or "practicing" or "mastered", "reason": "..."},
           "missed": [{"prompt": "...", "answer": "..."}, ...]}.
          The verdict is evidence-only: mastered means they answered essentially
          everything, applied included; practicing means solid recall with gaps;
          learning means the foundations aren't there yet. Judge only questions
          actually attempted — an abandoned quiz with no answers is "learning".
          missed is one entry per question they got wrong or skipped, phrased as a
          clean flashcard. The recap body: how it went against last time, what to
          shore up — short, written for the learner to reread.
        TEXT
      end

      def recap_fallback_title
        study_topic ? "Quiz — #{study_topic.title}" : "Quiz — #{(material_note || note).title.presence || "a note"}"
      end

      # The recap is filed where its material is, so a quiz on a Health note
      # lands in Health without anyone picking a section.
      def filing_sources = [ material_note || note ]
  end
end
