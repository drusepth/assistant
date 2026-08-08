module Tool
  # Infinite patient 1:1 tutoring, for the user or their kid — the service
  # the wealthy buy by the hour. The proving tool for the chat kind (D29),
  # and the owned-memory moat working as designed: the system prompt carries
  # the Education lens — Learn-something plans, their step progress, and the
  # recap Notes past sessions saved — so Tuesday's tutor knows Monday
  # struggled with fractions. Recaps are what future sessions read: saving
  # one is how a session becomes memory.
  class Tutor < ChatBase
    self.title = "Study with a tutor"
    self.description = "An infinitely patient 1:1 tutor that knows your plan and remembers last time."
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

    private
      def system_prompt
        parts = [ BEHAVIOR ]
        parts << "Today's session topic: #{inputs[:topic]}"
        parts << "The learner: #{inputs[:learner]}" if inputs[:learner].present?
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
        <<~TEXT
          The session is wrapping up. Respond with a JSON object
          {"recap": {"title": "...", "body": "..."}}.
          The body: what we covered, what clicked, what to practice before next
          time — short, concrete, written for the learner to reread later. The
          title like "Tutoring recap — <topic>".
        TEXT
      end

      def recap_fallback_title = "Tutoring recap — #{inputs[:topic]}"
  end
end
