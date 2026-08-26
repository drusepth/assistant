module Education
  # The paperwork assembler (D-learning-record): portfolio, transcript, and
  # hours log built deterministically from the spine and study_logs — the
  # model, when present, writes portfolio narrative paragraphs and nothing
  # else. Every artifact opens with the framing that is not negotiable:
  # evidence, never accreditation.
  class Record
    ARTIFACTS = %w[ portfolio transcript hours_log ].freeze

    FRAMING = "A record of demonstrated work, generated from this household's own learning data. " \
      "It is evidence — not a diploma, and not accreditation."

    def initialize(user:, artifact:, since: nil, profile: nil)
      @user = user
      @artifact = artifact.to_s
      raise ArgumentError, "unknown artifact #{artifact.inspect}" unless ARTIFACTS.include?(@artifact)

      @since = since
      @profile = profile
    end

    def title
      period = @since ? " since #{@since.strftime("%B %Y")}" : ""
      "#{@artifact.humanize} — #{@user.name}#{period}"
    end

    def build
      [ header, public_send("#{@artifact}_body") ].join("\n\n")
    end

    def header
      <<~TEXT.strip
        # #{title}

        Generated #{Date.current.strftime("%B %-d, %Y")}. #{FRAMING}
      TEXT
    end

    def transcript_body
      sections = subjects.map do |subject|
        mastered = subject.ordered_leaves.select { |topic| topic.mastered? || topic.rusty? }
        lines = [ "## #{subject.title} (#{subject.status})" ]
        lines << "From the open curriculum commons (#{subject.commons_key})." if subject.commons_key
        lines << "#{subject.mastered_count} of #{subject.leaf_count} topics mastered."
        mastered.each do |topic|
          date = topic.mastered_on ? topic.mastered_on.strftime("%b %-d, %Y") : "date unrecorded"
          lines << "- #{topic.title} — mastered #{date} (evidence: #{evidence_label(topic)})"
        end
        lines.join("\n")
      end
      sections.presence&.join("\n\n") || "No subjects on record yet."
    end

    def hours_log_body
      logs = @user.study_logs.order(:on)
      logs = logs.where(on: @since..) if @since
      return "No study time on record yet." if logs.none?

      by_month = logs.group_by { |log| log.on.beginning_of_month }
      body = by_month.map do |month, rows|
        lines = [ "## #{month.strftime("%B %Y")} — #{format_minutes(rows.sum(&:minutes))}" ]
        rows.group_by(&:subject).each do |subject, subject_rows|
          label = subject&.title || "General study"
          lines << "- #{label}: #{format_minutes(subject_rows.sum(&:minutes))} across #{subject_rows.size} sessions"
        end
        lines.join("\n")
      end
      total = "**Total: #{format_minutes(logs.sum(&:minutes))}.**"
      ([ total ] + body).join("\n\n")
    end

    def portfolio_body
      sections = subjects.map do |subject|
        recent = subject.ordered_leaves.select(&:mastered?).sort_by { |topic| topic.mastered_on || Date.new(1) }.last(5)
        lines = [ "## #{subject.title}" ]
        lines << subject.interest_frame if subject.interest_frame.present?
        lines << "Progress: #{subject.mastered_count} of #{subject.leaf_count} topics mastered."
        lines << narrative_for(subject)
        recent.each { |topic| lines << "- #{topic.title}#{" — #{topic.summary}" if topic.summary.present?}" }
        lines.compact.join("\n")
      end
      sections.presence&.join("\n\n") || "No subjects on record yet."
    end

    private
      def subjects
        scope = @user.subjects.where(status: %i[ active finished ]).order(:created_at)
        @since ? scope.where(created_at: @since..).or(scope.where(updated_at: @since..)) : scope
      end

      def evidence_label(topic)
        { "quiz" => "retrieval quiz", "tutor" => "tutor checkpoint", "teach_back" => "taught it back",
          "self_marked" => "learner's own call", "placement" => "placement" }[topic.mastery_evidence] || "unrecorded"
      end

      def format_minutes(minutes)
        hours = minutes / 60
        rest = minutes % 60
        hours.positive? ? "#{hours} h #{rest} min" : "#{rest} min"
      end

      # The one model touch (D-learning-record): a narrative paragraph per
      # portfolio subject. Absent or failing model = the numbers stand alone.
      def narrative_for(subject)
        return nil unless @artifact == "portfolio" && @profile

        mastered = subject.ordered_leaves.select(&:mastered?).map(&:title)
        return nil if mastered.empty?

        response = @profile.client.chat([
          { role: "system", content: "You write one warm, factual paragraph for a homeschool portfolio. " \
            "Only what the data supports — no invented projects, no grades, no superlatives. Respond with JSON {\"paragraph\": \"...\"}." },
          { role: "user", content: "Subject: #{subject.title}\nLearner frame: #{subject.interest_frame}\nMastered topics: #{mastered.join("; ")}" }
        ], json: true)
        response["paragraph"].to_s.strip.presence
      rescue Llm::Error
        nil
      end
  end
end
