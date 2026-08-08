module Tool
  # The mental-health check-in (docs/HEALTH.md §6): a private place to talk
  # through what's on your mind — guided (unpack a stressor, a breathing
  # exercise, prep for real therapy) or just listened to. Scoped hard as
  # support, not therapy (D31): the model never diagnoses, never plays
  # clinician, encourages a human therapist when things sound heavy, and
  # the crisis-resources notice is appended by code at session start — the
  # guardrail never depends on model behavior. Past recap Notes are the
  # continuity (the owned-memory moat, tutor-style): Tuesday's check-in
  # knows what Monday's carried.
  class CheckIn < ChatBase
    self.title = "Check in"
    self.description = "Talk through what's on your mind — guided or just heard. Support, not therapy."
    self.section_slugs = %w[ health ]
    self.quick_replies = [
      "Help me unpack something stressful",
      "Guide me through a breathing exercise",
      "Help me prep for a therapy session",
      "Just listen for a bit"
    ]

    input :about,
      label: "What's on your mind?",
      hint: "Optional — or leave it blank and just start talking."

    MAX_RECAPS = 3
    MAX_RECAP_CHARS = 400

    CRISIS_NOTICE = "Check-ins are supportive self-reflection, not therapy or medical care. " \
      "If you're in crisis or thinking about harming yourself, reach out now: in the US, " \
      "call or text 988 (Suicide & Crisis Lifeline) — elsewhere, your local emergency or " \
      "crisis line.".freeze

    BEHAVIOR = <<~PROMPT.freeze
      You are the check-in feature of a private, self-hosted life assistant —
      a warm, steady companion for talking through what's on someone's mind.
      You are NOT a therapist, counselor, or medical professional, and you
      never present yourself as one. Rules of the room:
      - Listen first. Reflect back what you heard, name feelings gently, ask
        one small question at a time. Short turns, plain conversational text —
        this is a dialogue, not an essay.
      - Never diagnose or suggest a condition ("that sounds like anxiety" is
        over the line), and never advise on medication or treatment.
      - Guided moves you know, when asked or when one would clearly help:
        unpacking a stressor (what happened, what it touched, what's theirs to
        control); a breathing or grounding exercise walked through one step
        per turn; a gratitude or wind-down reflection; sorting out what to
        bring up in a session with a real therapist.
      - "Just listen" means just listen: no fixing, no silver linings, no
        advice until asked.
      - When something sounds heavy or persistent — weeks of low mood, panic,
        trauma, grief that isn't moving — say plainly and kindly that a human
        therapist is the right next step, and that the find-a-doctor tool in
        this app can help find one. Encourage, never pressure, and stay with
        them either way.
      - If self-harm, suicide, abuse, or danger to anyone comes up: set the
        exercise aside, stay warm and direct, and point to crisis help now —
        in the US, call or text 988; elsewhere, the local emergency number or
        crisis line. You cannot handle a crisis, and saying so kindly is the
        caring move.
      - Stay honest about what this is: a private space to think out loud.
        Support, not treatment.
    PROMPT

    # The one guardrail that must not depend on the model: the crisis notice
    # opens every session, rendered in the transcript but never sent to the
    # model (notices never are).
    def call
      run.tool_run_messages.create!(role: :notice, content: CRISIS_NOTICE)
      super
    end

    private
      def system_prompt
        parts = [ BEHAVIOR ]
        parts << "What's on their mind today, in their words: #{inputs[:about]}" if inputs[:about].present?
        if past_recaps.any?
          listing = past_recaps.map { |note| "- #{note.title}: #{note.body.truncate(MAX_RECAP_CHARS)}" }.join("\n")
          parts << "Recaps of past check-ins, newest first — continuity, not an agenda; " \
                   "follow up only if they want to:\n#{listing}"
        end
        parts.join("\n\n")
      end

      def opening_instruction
        "Open the check-in: a brief, warm greeting. If a past recap holds something worth " \
          "following up on, offer — don't push — to pick it back up; otherwise invite them to " \
          "share what's on their mind, or offer a guided option (unpacking something, a " \
          "breathing exercise, or just being heard). Two or three sentences, nothing clinical."
      end

      def recap_instruction
        <<~TEXT
          The check-in is wrapping up. Respond with a JSON object
          {"recap": {"title": "...", "body": "..."}}.
          The body: what came up, what seemed to help, anything worth returning
          to next time — short, gentle, written for the user to reread. Title
          like "Check-in recap — <theme>". Same boundaries as the session: no
          diagnoses, no clinical language.
        TEXT
      end

      def recap_fallback_title = "Check-in recap"

      # Recaps from earlier check-in runs (the previous_recap query shape,
      # widened): the session's memory, read newest-first.
      def past_recaps
        @past_recaps ||= begin
          earlier = user.tool_runs.where(tool_slug: self.class.slug).where.not(id: run.id).select(:id)
          ToolRunItem.where(tool_run_id: earlier, item_type: "Note")
            .order(created_at: :desc, id: :desc).limit(MAX_RECAPS).filter_map(&:item)
        end
      end
  end
end
