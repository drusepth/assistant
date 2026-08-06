module Tool
  # The Q9 reframe of "find meetups nearby" (docs/HOBBIES.md §3): Tier A, so
  # no live listings — instead a guide to where people who share the hobby
  # actually gather, with search recipes and check-this-week follow-ups.
  # The prompt forbids inventing specific local clubs or schedules; when
  # capabilities land (Q9), this same tool upgrades to real listings.
  class FindYourPeople < Base
    self.title = "Find your people"
    self.description = "Where the folks who share this hobby gather — and how to go meet them."
    self.section_slugs = %w[ hobbies ]
    self.kind = :draft

    input :hobby, kind: :hobby, required: true, label: "Which hobby?"
    input :area, label: "Your city or area",
      hint: "Optional — tailors where to look."

    MAX_FOLLOW_UPS = 3
    MAX_NOTES = 5
    MAX_NOTE_CHARS = 300

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the find-your-people feature of a private, self-hosted life
      assistant. The user wants to find other people who share a hobby — a club,
      class, group, or community. You cannot browse the web, so be honest about
      what you know: recommend kinds of places and well-known platforms or
      organizations, and give concrete search recipes ("search Meetup for …",
      "ask at the library front desk about …") — never invent a specific local
      club, venue, address, schedule, or price. Respond with a JSON object:
      {"guide": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The guide's body covers, with short headed lists: where people who do this
      hobby actually gather, online and in person, specific to the hobby and
      tailored to the user's area when given; how to vet a group and what a
      first visit looks like; and two or three questions to ask when reaching
      out. Practical and encouraging, no filler. follow_ups are at most #{MAX_FOLLOW_UPS} small
      concrete actions ("check Meetup for climbing groups this week"), each
      completable in a day; set due_on only for natural time-boxes, resolved
      against today's date.
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
        parts << "The hobby: #{hobby_name}"
        parts << "Where the user is: #{inputs[:area]}" if inputs[:area].present?
        if notes.any?
          listing = notes.map { |note| "- #{note.title.presence || "Note"}: #{note.body.truncate(MAX_NOTE_CHARS)}" }.join("\n")
          parts << "What they've noted about this hobby (for tailoring, e.g. skill level):\n#{listing}"
        end
        parts.join("\n\n")
      end

      def handle(response)
        body = response.dig("guide", "body")
        raise Llm::Error, "The model didn't return a guide — try again." if body.blank?

        guide = record(user.notes.create!(
          title: response.dig("guide", "title").presence || "Finding your people — #{hobby_name}",
          body: body
        ))
        guide.sections = filing

        Array(response["follow_ups"]).first(MAX_FOLLOW_UPS).each do |step|
          next unless step.is_a?(Hash) && step["title"].present?

          due_on = parsed_date(step["due_on"])
          task = record(user.tasks.create!(
            title: step["title"].to_s, due_on: due_on,
            bucket: due_on && due_on <= Date.current ? :today : :later
          ))
          task.sections = filing
        end
      end

      def hobby_name = lens&.name || inputs[:hobby].to_s.squish

      # Matches an existing lens for filing and context; deliberately never
      # creates one — only Start-a-hobby and the capture UI do that.
      def lens = defined?(@lens) ? @lens : (@lens = Hobbies::Lens.named(inputs[:hobby]))

      def notes
        @notes ||= lens ? Note.visible_to(user).in_section(lens.id).order(updated_at: :desc).limit(MAX_NOTES).to_a : []
      end

      def filing
        @filing ||= (self.class.section_records + [ lens ].compact).uniq
      end
  end
end
