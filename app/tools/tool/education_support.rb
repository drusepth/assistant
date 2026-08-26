module Tool
  # The helper layer the education tools share (docs/EDUCATION_PLAN.md §6):
  # reading the spine safely, describing it to the model, and the writes a
  # wrap-up click is allowed to make — mastery through Topic#advance! with
  # named evidence, review cards capped and allowlisted, and the study_log
  # row that outlives the transcript (D-learning-record).
  module EducationSupport
    MAX_MINTED_ITEMS = 5
    # Placement and checkpoints only ever move a topic forward — demotion is
    # FSRS's job (D-mastery-evidence), never a conversation's.
    LADDER = %w[ unseen learning practicing mastered ].freeze

    private
      # The learner's own topic — never a grantee's; studying is first-person.
      def chosen_topic(input_name = :topic_id)
        return nil if inputs[input_name].blank?

        @chosen_topic ||= Topic.joins(:subject).where(subjects: { user_id: user.id })
          .find_by(id: inputs[input_name]) ||
            raise(Llm::Error, "That topic is gone from your syllabus — pick another.")
      end

      def chosen_study_subject(input_name = :subject_id)
        return nil if inputs[input_name].blank?

        @chosen_study_subject ||= user.subjects.find_by(id: inputs[input_name]) ||
          raise(Llm::Error, "That subject is gone — pick another.")
      end

      # What the model needs to teach *this* learner *this* topic: the tree
      # position, the states around it, and the interest frame (§7 — framing
      # tunes presentation; advancement still gates on evidence).
      def topic_context(topic)
        subject = topic.subject
        parts = [ "Today's topic: #{topic.title} (currently #{topic.mastery.humanize.downcase})" ]
        parts << "What mastering it means: #{topic.summary}" if topic.summary.present?
        parts << "Its strand: #{topic.parent.title}" if topic.parent
        parts << "The subject: #{subject.title}"
        parts << interest_frame_line(subject)
        neighbors = subject.ordered_leaves.reject { |leaf| leaf == topic }
        mastered = neighbors.select(&:mastered?).first(6).map(&:title)
        parts << "Already mastered (build on these): #{mastered.join("; ")}" if mastered.any?
        upcoming = neighbors.select(&:unseen?).first(3).map(&:title)
        parts << "Coming later (don't teach ahead into): #{upcoming.join("; ")}" if upcoming.any?
        parts.compact.join("\n")
      end

      def interest_frame_line(subject)
        return nil if subject.interest_frame.blank?

        "Who's learning, and through what lens (shape examples and register to this): #{subject.interest_frame}"
      end

      # The whole tree with ids, for prompts that must point back at rows
      # (placement). Ids are the contract; titles are for the model's eyes.
      def tree_listing(subject)
        subject.strands.includes(:children).flat_map { |strand|
          if strand.children.any?
            [ "#{strand.title}:" ] + strand.children.map { |topic| "  [#{topic.id}] #{topic.title} — #{topic.mastery}" }
          else
            [ "[#{strand.id}] #{strand.title} — #{strand.mastery}" ]
          end
        }.join("\n")
      end

      # A checkpoint or placement mark, applied only forward along the
      # ladder and only inside the learner's own tree.
      def apply_mark(topic, state, evidence:)
        return unless topic && LADDER.include?(state.to_s)
        return if LADDER.index(state.to_s) <= (LADDER.index(topic.mastery) || LADDER.size)

        topic.advance!(to: state, evidence: evidence)
      end

      # Misses become tomorrow's retrieval practice — capped, stripped, and
      # scheduled from scratch by FSRS (D-review-scheduler).
      def mint_review_items(topic, entries, kind: :flash)
        Array(entries).first(MAX_MINTED_ITEMS).each do |entry|
          next unless entry.is_a?(Hash) && entry["prompt"].present?
          next if topic.review_items.exists?(prompt: entry["prompt"].to_s)

          record(user.review_items.create!(
            topic: topic, kind: kind,
            prompt: entry["prompt"].to_s, answer: entry["answer"].to_s.presence
          ))
        end
      end

      # The durable line (D-learning-record): the transcript prunes at 90
      # days; this row is what the hours log reads.
      def log_study_session(subject:, topic: nil, activity:)
        user.study_logs.create!(
          subject: subject, topic: topic, activity: activity,
          on: Date.current, minutes: session_minutes, note: self.class.title
        )
      end

      # Honest-enough duration: first message to last, clamped to something
      # a session could plausibly have been.
      def session_minutes
        messages = run.tool_run_messages.conversational.ordered
        first_at = messages.first&.created_at || run.created_at
        last_at = messages.last&.created_at || Time.current
        ((last_at - first_at) / 60).round.clamp(3, 120)
      end
  end
end
