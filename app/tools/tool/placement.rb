module Tool
  # Find my edge (docs/EDUCATION_PLAN.md §6): a short adaptive conversation
  # that stamps a subject's starting mastery, so the returning adult starts
  # algebra at algebra, not at counting. Generous by design — mastery can
  # always be re-proven later; boredom in week one is the killer. Marks are
  # evidence-typed "placement" and only ever move a topic forward, and only
  # when the learner clicks Finish (D20).
  class Placement < ChatBase
    self.title = "Find my edge"
    self.description = "A short placement conversation — start where you actually are, not at a grade level."
    self.section_slugs = %w[ education ]
    self.quick_replies = [
      "That one's easy",
      "I don't know that yet",
      "Skip this strand"
    ]

    input :subject_id, kind: :study_subject, required: true, label: "Which subject?"

    def self.recap_button_label(_run) = "Finish & set my starting points"

    def self.recap_pending_label = "Placing…"

    def self.recap_hint
      "Finishing marks what you already know as mastered — generously — so the syllabus starts at your edge."
    end

    BEHAVIOR = <<~PROMPT.freeze
      You are the placement feature of a private, self-hosted personal school.
      Find the learner's edge across a subject quickly and kindly:
      - Work strand by strand: one or two questions each, starting mid-strand and
        stepping easier or harder by their answer. Skip obviously-below territory.
      - Short questions with checkable answers; accept "no idea" instantly and
        move on — placement is mapping, never testing.
      - Keep the whole thing under ~10 questions unless they want more, then say
        they can finish to set their starting points.
      - Plain conversational text, no markdown tables, no LaTeX. Reassure without
        condescending: not knowing is exactly what this is for.
    PROMPT

    def call
      chosen_study_subject
      super
    end

    def recap!
      subject = chosen_study_subject
      response = profile.client.chat(recap_messages, json: true)
      body = response.dig("recap", "body")
      raise Llm::Error, "The model couldn't write up the placement — try again." if body.blank?

      leaves = subject.ordered_leaves.index_by(&:id)
      Array(response["placements"]).each do |placement|
        next unless placement.is_a?(Hash)

        apply_mark(leaves[placement["topic_id"].to_i], placement["state"].to_s, evidence: "placement")
      end
      log_study_session(subject: subject, activity: :lesson)
      create_note(title: response.dig("recap", "title").presence || recap_fallback_title, body: body)
    end

    private
      include EducationSupport

      def system_prompt
        subject = chosen_study_subject
        [
          BEHAVIOR,
          "The subject and its syllabus — topic ids in brackets are the contract; refer to topics by title when talking:",
          tree_listing(subject),
          interest_frame_line(subject)
        ].compact.join("\n\n")
      end

      def opening_instruction
        "Open the placement: one sentence on what this is and that guessing wrong costs nothing, then the first question."
      end

      def recap_instruction
        <<~TEXT
          The placement is over. Respond with a JSON object:
          {"recap": {"title": "Placement — <subject>", "body": "..."},
           "placements": [{"topic_id": 123, "state": "learning" or "practicing" or "mastered"}, ...]}.
          Use the bracketed topic ids from the syllabus listing. Be generous:
          confident answers make the whole territory beneath them "mastered";
          shaky ground is "practicing"; leave anything untested and above their
          edge out entirely. The recap body: where their edge sits and where the
          syllabus will start — short, warm, written for the learner.
        TEXT
      end

      def recap_fallback_title = "Placement — #{chosen_study_subject.title}"

      def filing_sources = [ chosen_study_subject ].compact
  end
end
