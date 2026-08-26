module Education
  # The learn-anything door's second author (D-curriculum-commons): where a
  # typed topic matches nothing on the shelf, the model drafts the strand →
  # topic outline and the learner owns it from there. One schema, two doors —
  # everything downstream is indifferent to which one a subject came through.
  class GenerateTree
    MAX_STRANDS = 6
    MAX_TOPICS = 8

    def initialize(subject:, profile:)
      @subject = subject
      @profile = profile
    end

    # One JSON call → the subject's own tree. Returns the created topics;
    # raises Llm::Error for callers to handle.
    def build!
      response = @profile.client.chat(messages, json: true)
      strands = parsed_strands(response["strands"])
      raise Llm::Error, "The model didn't return a curriculum — try again." if strands.none?

      @subject.transaction do
        strands.each_with_index.flat_map do |(strand_title, entries), strand_index|
          parent = @subject.topics.create!(title: strand_title, position: strand_index + 1)
          entries.each_with_index.map do |entry, index|
            @subject.topics.create!(
              parent: parent, title: entry.fetch("title"),
              summary: entry["summary"].to_s.strip.presence, position: index + 1
            )
          end
        end
      end
    end

    private
      def messages
        [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ]
      end

      def system_prompt
        <<~PROMPT
          You are the curriculum-planning feature of a private, self-hosted life
          assistant — a personal school. The user names something they want to learn;
          you draft their curriculum as strands (units) of topics, in the order the
          ideas build. Respond with a JSON object:
          {"strands": [{"title": "...",
                        "topics": [{"title": "...", "summary": "..."}, ...]}, ...]}.
          Use 3 to #{MAX_STRANDS} strands of 3 to #{MAX_TOPICS} topics each — enough to genuinely
          cover the subject at the learner's level, never padding. Each topic is one
          masterable idea or skill; its summary is one sentence stating what mastering
          it means — something checkable ("compute X", "explain Y", "do Z"), never
          "understand" or "learn more about". Order topics so each builds on what came
          before, and end the final strand with a capstone topic where the learner
          produces or does something real that proves the subject stuck.
        PROMPT
      end

      def user_prompt
        parts = [ "The subject: #{@subject.title}" ]
        parts << "About this learner and their angle (shape examples, framing, and pace to this): #{@subject.interest_frame}" if @subject.interest_frame.present?
        parts << "More context: #{@subject.description}" if @subject.description.present?
        parts.join("\n")
      end

      def parsed_strands(strands)
        Array(strands).first(MAX_STRANDS).filter_map do |strand|
          next unless strand.is_a?(Hash) && strand["title"].present?

          entries = Array(strand["topics"]).first(MAX_TOPICS)
            .select { |entry| entry.is_a?(Hash) && entry["title"].present? }
          next if entries.none?

          [ strand["title"].to_s, entries ]
        end
      end
  end
end
