module Education
  # The personalization pass on an enrolled commons subject
  # (D-curriculum-commons): the outline's *summaries* get reframed through
  # the learner's interest frame — fractions through recipe scaling for the
  # cook — while the structure stays the commons' own, auditable against the
  # YAML it was copied from. Framing tunes presentation; mastery still gates
  # on retrieval (§7's structural caveat).
  class PersonalizeTree
    MAX_SUMMARY_CHARS = 300

    def initialize(subject:, profile:)
      @subject = subject
      @profile = profile
    end

    def apply!
      return if @subject.interest_frame.blank?

      leaves = @subject.ordered_leaves
      return if leaves.empty?

      response = @profile.client.chat(messages(leaves), json: true)
      by_id = leaves.index_by(&:id)
      Array(response["topics"]).each do |row|
        next unless row.is_a?(Hash)

        topic = by_id[row["id"].to_i]
        summary = row["summary"].to_s.strip
        topic.update!(summary: summary.truncate(MAX_SUMMARY_CHARS)) if topic && summary.present?
      end
    end

    private
      def messages(leaves)
        listing = leaves.map { |topic| "[#{topic.id}] #{topic.title} — #{topic.summary}" }.join("\n")
        [
          { role: "system", content: <<~PROMPT },
            You are the curriculum-personalization feature of a private, self-hosted
            personal school. Rewrite each topic's one-sentence summary through this
            learner's world — their interests supply the examples and the register —
            while keeping exactly what mastering the topic means: the same checkable
            skill, never a softer one. Respond with a JSON object:
            {"topics": [{"id": 123, "summary": "..."}, ...]}.
            Keep every id you were given; where the original summary already fits the
            learner, return it unchanged.
          PROMPT
          { role: "user", content: "The learner: #{@subject.interest_frame}\nThe subject: #{@subject.title}\n\n#{listing}" }
        ]
      end
  end
end
