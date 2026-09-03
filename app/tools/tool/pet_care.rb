module Tool
  # The standing conversation about a pet (D-pet-primitive, PETS_PLAN §6).
  # Same shape as the mental-health check-in and the same discipline: the
  # scope line is **preparation and comprehension, never diagnosis**, and it
  # matters more here, not less. A person with a worrying symptom can describe
  # it; a dog can't, the owner is guessing from behaviour, and the cost of a
  # confident wrong answer is an animal that didn't go to the vet.
  #
  # Three guarantees don't depend on the model behaving:
  #   1. an emergency notice opens every session, code-authored;
  #   2. anything on the shipped toxics list is answered by a *lookup* before
  #      the model speaks (Datasets::PetToxics);
  #   3. every session carries a find-a-vet card — the model can say the
  #      words, the card makes them one click.
  class PetCare < ChatBase
    self.title = "Ask about your pet"
    self.description = "Talk through food, behaviour, routines and what to watch for. Never a diagnosis."
    self.section_slugs = %w[ health ]
    self.quick_replies = [
      "Is this food safe for them?",
      "Help me plan their routine",
      "What should I ask the vet?",
      "They're doing something new — help me think it through"
    ]

    input :pet_id, kind: :pet, required: true, label: "Which pet?"
    input :about,
      label: "What's on your mind?",
      hint: "Optional — or leave it blank and just start talking."

    MAX_RECAPS = 3
    MAX_RECAP_CHARS = 400

    EMERGENCY_NOTICE = "This is a place to think out loud about your pet's care — never a diagnosis, " \
      "and never a reason to wait. Go to a vet now for: collapse, laboured breathing, a swollen or " \
      "hard belly, repeated retching without bringing anything up, a cat straining in the litter tray, " \
      "seizures, heavy bleeding, or a suspected poisoning. " \
      "#{Datasets::PetToxics::POISON_LINE}".freeze

    BEHAVIOR = <<~PROMPT.freeze
      You are the pet-care feature of a private, self-hosted life assistant.
      You help an owner think clearly about their animal's food, routine,
      training, comfort and questions for the vet. You are NOT a veterinarian
      and never present yourself as one. Rules of the room:
      - Never diagnose, never name a suspected condition, never suggest a
        medication or a dose — not even an over-the-counter one, and not even
        when asked directly. Human medicines poison pets.
      - When something sounds like it could be medical — a symptom, a change in
        eating, drinking, breathing, toileting, weight or behaviour, anything
        that has lasted or is getting worse — say plainly that this is a
        question for the vet, help them describe it accurately (when it
        started, how often, what changed around it), and stop there. Helping
        them get seen is the win; guessing is the loss.
      - What you are genuinely good at, and should lean into: routines and
        schedules, house-training and enrichment, what to ask at the next
        appointment, how to introduce a new food or a new animal, what to pack
        for the sitter, reading a label, weighing a decision the owner has
        already been given by their vet.
      - Short conversational turns. One question at a time. Warm and practical,
        never clinical, never alarmist.
      - You know only what the record below says. Don't invent history, and say
        when you're missing something that would change the answer.
    PROMPT

    def call
      run.tool_run_messages.create!(role: :notice, content: EMERGENCY_NOTICE)
      super
      offer_vet
    end

    # The toxics guardrail (2): before the model answers, the app answers.
    # A lookup over a shipped list says the same true thing every time, at the
    # top of the reply, whatever the model goes on to say.
    def reply!
      warn_about_toxics
      super
    end

    private
      def pet = @pet ||= chosen_pet

      def warn_about_toxics
        last = run.tool_run_messages.user_role.ordered.last
        return if last.blank?

        found = Datasets::PetToxics.current.scan(last.content, species: pet.species)
        return if found.empty?

        run.tool_run_messages.create!(role: :notice, content: toxics_notice(found))
      end

      def toxics_notice(found)
        lines = found.map { |entry| "#{entry.label.capitalize}: #{entry.note}" }
        urgency = if found.any?(&:emergency?)
          "If #{pet.name} has already had any of this, call now — don't wait for symptoms."
        else
          "If #{pet.name} has already had some, call your vet and say how much and when."
        end
        "Not safe for a #{pet.species_label.downcase}. #{lines.join(" ")} #{urgency} #{Datasets::PetToxics::POISON_LINE}"
      end

      def system_prompt
        parts = [ BEHAVIOR, "The pet:\n#{pet_context(pet)}" ]
        parts << "What's on the owner's mind today, in their words: #{inputs[:about]}" if inputs[:about].present?
        if past_recaps.any?
          listing = past_recaps.map { |note| "- #{note.title}: #{note.body.truncate(MAX_RECAP_CHARS)}" }.join("\n")
          parts << "Recaps of past sessions about this pet, newest first — continuity, not an agenda:\n#{listing}"
        end
        parts.join("\n\n")
      end

      def opening_instruction
        "Open the conversation: a brief, warm greeting that shows you know which animal this is. " \
          "If a past recap holds something worth following up on, offer — don't push — to pick it " \
          "back up; otherwise invite the question. Two or three sentences."
      end

      def recap_instruction
        <<~TEXT
          The session is wrapping up. Respond with a JSON object
          {"recap": {"title": "...", "body": "..."}}.
          The body: what came up about this pet, what was decided, and anything
          worth raising with the vet next time — short and practical. Title like
          "#{pet.name} — <theme>". Same boundaries as the session: no diagnoses.
        TEXT
      end

      def recap_fallback_title = "#{pet.name} — care notes"

      # Recaps file under the pet's lens as well as Health, so the next
      # session — and the vet-prep sheet — find them. (Own memo: the base
      # memoizes into @filing, so reusing that name would swallow super.)
      def filing
        @pet_filing ||= (super + [ pet.section ]).uniq
      end

      def offer_vet
        store_next_tools(
          [ {
            "slug" => "vet_visit_prep",
            "inputs" => { "pet_id" => pet.id.to_s },
            "reason" => "When it's a question for the vet — the sheet to walk in with."
          } ],
          allowed: %w[ vet_visit_prep ]
        )
      end

      def past_recaps
        @past_recaps ||= begin
          earlier = user.tool_runs.where(tool_slug: self.class.slug).where.not(id: run.id).select(:id)
          ToolRunItem.where(tool_run_id: earlier, item_type: "Note")
            .order(created_at: :desc, id: :desc).limit(MAX_RECAPS).filter_map(&:item)
            .select { |note| note.section_ids.include?(pet.section_id) }
        end
      end
  end
end
