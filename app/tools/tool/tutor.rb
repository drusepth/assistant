module Tool
  # Infinite patient 1:1 tutoring, for the user or their kid — the service
  # the wealthy buy by the hour, and the two-sigma half of the education
  # plan. The proving tool for the chat kind (D29), and the owned-memory
  # moat working as designed: the system prompt carries the Education lens,
  # and — entered from a syllabus row — the topic's place in the learner's
  # own tree (D-education-spine), the states around it, and the interest
  # frame, so Tuesday's tutor knows Monday struggled with fractions.
  #
  # Wrapping up is where a session becomes memory (D20 — the click is the
  # consent): the recap Note future sessions read, review cards mined from
  # what was covered (D-review-scheduler), a checkpoint verdict that can
  # move the topic forward on tutor evidence, and the study_log row the
  # hours log outlives the transcript by (D-learning-record).
  class Tutor < ChatBase
    self.title = "Study with a tutor"
    self.description = "An infinitely patient 1:1 tutor that knows your syllabus and remembers last time."
    self.section_slugs = %w[ education ]
    self.quick_replies = [
      "I don't get it — can you explain it another way?",
      "Show me an example",
      "Quiz me",
      "Got it — what's next?"
    ]

    input :topic, required: true,
      label: "What are we working on?",
      hint: "“Algebra homework”, “Spanish practice”, “the fractions unit”."
    input :learner,
      label: "Who's learning?",
      hint: "Optional — “me”, “my 9-year-old”."
    input :topic_id, kind: :topic,
      label: "Tie it to your syllabus",
      hint: "Optional — the session then knows the topic's place in your tree, and wrapping up can move its mastery."

    BEHAVIOR = <<~PROMPT.freeze
      You are the tutor feature of a private, self-hosted life assistant — an
      infinitely patient 1:1 tutor. Rules of the room:
      - Socratic first: before explaining, ask what the learner thinks or already
        knows; explain once the questions have done their work.
      - Homework gets guided, never done: lead toward the answer step by step and
        let the learner take it.
      - Adapt language and depth to the learner; for a child, short sentences and
        concrete examples.
      - Short turns — this is a dialogue, not a lecture. One idea, then a
        question. Plain conversational text only: no markdown tables, no LaTeX.
      - A wrong answer is information: name what was right in the attempt, then
        aim the next question at the gap.
      - Stay warm, stay honest, and stay on the session's topic; steer back
        gently when things drift.
    PROMPT

    def recap!
      response = profile.client.chat(recap_messages, json: true)
      body = response.dig("recap", "body")
      raise Llm::Error, "The model couldn't write a recap — try again." if body.blank?

      if (topic = chosen_topic)
        mint_review_items(topic, response["review_items"])
        apply_mark(topic, response.dig("checkpoint", "state").to_s, evidence: "tutor") if session_probed?
        log_study_session(subject: topic.subject, topic: topic, activity: :tutor)
      end
      create_note(title: response.dig("recap", "title").presence || recap_fallback_title, body: body)
    end

    private
      include EducationSupport

      def system_prompt
        parts = [ BEHAVIOR ]
        parts << "Today's session topic: #{inputs[:topic]}"
        parts << "The learner: #{inputs[:learner]}" if inputs[:learner].present?
        if (topic = chosen_topic)
          parts << "This session sits in the learner's own syllabus:\n#{topic_context(topic)}"
        end
        context = section_context
        unless context.empty?
          parts << "What's tracked in Education — study plans, their progress, and recaps of past sessions. Use it to pick up where things left off:\n#{context.to_prompt}"
        end
        parts.join("\n\n")
      end

      def opening_instruction
        "Open the session: greet the learner briefly, and — drawing on the tracked data when there is any — say where things stand and ask where they want to start. Two or three sentences."
      end

      def recap_instruction
        extras = chosen_topic ? syllabus_recap_extras : ""
        <<~TEXT
          The session is wrapping up. Respond with a JSON object
          {"recap": {"title": "...", "body": "..."}#{extras.present? ? "," : "}."}
          #{extras}
          The recap body: what we covered, what clicked, what to practice before next
          time — short, concrete, written for the learner to reread later. The
          title like "Tutoring recap — <topic>".
        TEXT
      end

      def syllabus_recap_extras
        <<~TEXT.strip
           "review_items": [{"prompt": "...", "answer": "..."}, ...],
           "checkpoint": {"state": "learning" or "practicing" or "mastered", "reason": "..."} or null}.
          review_items are 2 to 4 clean flashcards on what this session actually
          covered — nothing the session didn't touch. checkpoint is your honest
          read of where the topic now stands, null unless the session gave real
          evidence (the learner answered things, worked examples, explained back);
          exposure alone is at most "learning".
        TEXT
      end

      # A checkpoint needs a session with the learner actually in it — a
      # hello-goodbye transcript is not evidence.
      def session_probed?
        run.tool_run_messages.conversational.user_role.count >= 3
      end

      def recap_fallback_title = "Tutoring recap — #{inputs[:topic]}"

      def filing_sources = [ chosen_topic&.subject ].compact
  end
end
