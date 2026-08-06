module Tool
  # The honest Tier-A version of "surface interesting new content"
  # (docs/HOBBIES.md §3): the model's evergreen craft knowledge applied to
  # the user's own context — past projects, notes, gear — never presented
  # as news. Output is an idea-menu Note; picking one is goal capture away.
  class WhatShouldIMakeNext < Base
    self.title = "What should I make next?"
    self.description = "A menu of project ideas sized to your skill, stash, and taste."
    self.section_slugs = %w[ hobbies ]
    self.kind = :draft

    input :hobby, kind: :hobby, label: "Which hobby?",
      hint: "Leave blank to draw on all of them."

    MAX_IDEAS = 8
    MAX_GOALS = 15
    MAX_NOTES = 8
    MAX_NOTE_CHARS = 300
    MAX_DOCUMENTS = 15

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the project-ideas feature of a private, self-hosted life assistant.
      The user wants ideas for what to make, build, or do next in a hobby.
      Respond with a JSON object:
      {"ideas": [{"title": "...", "pitch": "...", "first_step": "..."}, ...]}.
      Give 5 to #{MAX_IDEAS} ideas sized to the skill their history suggests — a step up
      from what they've already finished, never a rehash of it. Prefer ideas that
      use materials, gear, and interests they actually mention; never claim they
      own something that isn't mentioned. Each pitch is one or two sentences on
      why it's worth making; each first_step is one concrete action doable today.
      Ideas are evergreen suggestions from your general knowledge — present
      nothing as current news, trends, or events.
    PROMPT

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        if lens.nil? && inputs[:hobby].blank? && [ goals, notes, documents ].all?(&:empty?)
          raise Llm::Error, "Nothing to work from yet — name a hobby, or start one with the Start-a-hobby tool."
        end

        parts = [ "Hobby: #{subject_name}" ]
        if goals.any?
          listing = goals.map { |goal| "- #{goal.title}#{" (finished)" if goal.done?}" }.join("\n")
          parts << "Their projects so far:\n#{listing}"
        end
        if notes.any?
          listing = notes.map { |note| "- #{note.title.presence || "Note"}: #{note.body.truncate(MAX_NOTE_CHARS)}" }.join("\n")
          parts << "Their notes:\n#{listing}"
        end
        if documents.any?
          parts << "Documents they keep:\n#{documents.map { |document| "- #{document.title}" }.join("\n")}"
        end
        parts.join("\n\n")
      end

      def handle(response)
        ideas = Array(response["ideas"]).select { |idea| idea.is_a?(Hash) && idea["title"].present? }.first(MAX_IDEAS)
        raise Llm::Error, "The model didn't return any ideas — try again." if ideas.none?

        note = record(user.notes.create!(title: "Project ideas — #{subject_name}", body: format_ideas(ideas)))
        note.sections = (self.class.section_records + [ lens ].compact).uniq
      end

      def format_ideas(ideas)
        ideas.map.with_index(1) do |idea, index|
          lines = [ "#{index}. #{idea["title"]}" ]
          lines << idea["pitch"].to_s if idea["pitch"].present?
          lines << "First step: #{idea["first_step"]}" if idea["first_step"].present?
          lines.join("\n")
        end.join("\n\n")
      end

      def subject_name = lens&.name || inputs[:hobby].presence&.squish || "your hobbies"

      def lens = defined?(@lens) ? @lens : (@lens = Hobbies::Lens.named(inputs[:hobby]))

      # Context narrows to the named hobby's lens when there is one,
      # otherwise spans everything filed under Hobbies.
      def context_section_ids
        @context_section_ids ||= lens ? [ lens.id ] : begin
          hobbies = Section.find_by!(slug: "hobbies")
          [ hobbies.id, *hobbies.children.ids ]
        end
      end

      def goals
        @goals ||= Goal.visible_to(user).in_section(context_section_ids).order(updated_at: :desc).limit(MAX_GOALS).to_a
      end

      def notes
        @notes ||= Note.visible_to(user).in_section(context_section_ids).order(updated_at: :desc).limit(MAX_NOTES).to_a
      end

      def documents
        @documents ||= Document.visible_to(user).in_section(context_section_ids).order(created_at: :desc).limit(MAX_DOCUMENTS).to_a
      end
  end
end
