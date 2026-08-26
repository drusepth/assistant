module Tool
  # The retrieval gate (D-mastery-evidence): a short quiz on one topic,
  # graded in conversation. Passing is what practicing → mastered *means*;
  # the misses become review cards aimed at the gap (D-review-scheduler).
  # Nothing writes until the learner clicks Finish — the recap click is the
  # explicit act that records the verdict (D20).
  class QuizMe < ChatBase
    self.title = "Quiz me"
    self.description = "A short retrieval check on one topic — the door mastery moves through."
    self.section_slugs = %w[ education ]
    self.quick_replies = [
      "Hint, please",
      "I don't know — show me",
      "Next question"
    ]

    input :topic_id, kind: :topic, required: true, label: "Which topic?"

    def self.recap_button_label(_run) = "Finish & record the result"

    def self.recap_pending_label = "Grading…"

    def self.recap_hint
      "Finishing grades the quiz, moves the topic's mastery on the evidence, and files what you missed for review."
    end

    BEHAVIOR = <<~PROMPT.freeze
      You are the quiz feature of a private, self-hosted personal school. Run a
      short retrieval check — recall causes learning, so the asking is the point.
      Rules of the room:
      - One question at a time, 4 to 6 questions total, then say the quiz is done
        and they can finish to record the result.
      - Ask for recall and application of this topic only — never trivia around it.
      - No teaching before an attempt: after they answer, say what was right, give
        the correct answer if they missed, one line of why, then move on.
      - "I don't know" is a fine answer and scores as a miss without ceremony.
      - Plain conversational text, no markdown tables, no LaTeX. Warm, brisk, honest.
    PROMPT

    def call
      chosen_topic
      super
    end

    def recap!
      topic = chosen_topic
      response = profile.client.chat(recap_messages, json: true)
      body = response.dig("recap", "body")
      raise Llm::Error, "The model couldn't grade the quiz — try again." if body.blank?

      state = response.dig("verdict", "state").to_s
      if Topic.masteries.key?(state) && state != topic.mastery
        topic.advance!(to: state, evidence: "quiz") unless demotion?(topic, state)
      end
      mint_review_items(topic, response["missed"])
      log_study_session(subject: topic.subject, topic: topic, activity: :review)
      create_note(title: response.dig("recap", "title").presence || recap_fallback_title, body: body)
    end

    private
      include EducationSupport

      def system_prompt
        [ BEHAVIOR, topic_context(chosen_topic) ].join("\n\n")
      end

      def opening_instruction
        "Open the quiz: one sentence naming the topic and how many questions, then question 1."
      end

      def recap_instruction
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
          clean flashcard. The recap body: how it went, what to shore up — short,
          written for the learner to reread.
        TEXT
      end

      def recap_fallback_title = "Quiz — #{chosen_topic.title}"

      # A quiz can hold a topic where it is or move it up; sliding a
      # mastered topic back is FSRS's call, never one bad afternoon's.
      def demotion?(topic, state)
        LADDER.index(state) && LADDER.index(topic.mastery) &&
          LADDER.index(state) < LADDER.index(topic.mastery)
      end

      def filing_sources = [ chosen_topic&.subject ].compact
  end
end
