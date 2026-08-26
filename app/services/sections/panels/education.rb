module Sections
  module Panels
    # The Education lead panel (docs/EDUCATION_PLAN.md §5): the hub reads
    # do → continue → begin → oversee → prove. The panel carries the data
    # each zone needs and hides the two tool cards it surfaces with better
    # context (the tutor rides every resume row; learn-something is the
    # learn-anything door).
    class Education < Panel
      RESUME_LIMIT = 3

      def hidden_tool_slugs = %w[ learn_something tutor ]

      def own_subjects
        @own_subjects ||= viewer.subjects.active.recently_studied_first.to_a
      end

      def paused_subjects
        @paused_subjects ||= viewer.subjects.paused.recently_studied_first.to_a
      end

      def finished_subjects
        @finished_subjects ||= viewer.subjects.finished.recently_studied_first.to_a
      end

      # The exact next topic per active subject — resuming is one tap,
      # because re-entry cost is what kills self-paced learning.
      def resume_entries
        @resume_entries ||= own_subjects.first(RESUME_LIMIT)
          .filter_map { |subject| (topic = subject.current_topic) && [ subject, topic ] }
      end

      def reviews_due_count
        @reviews_due_count ||= viewer.review_items.due.count
      end

      # ~10 phone-sized minutes is the habit the hub banks on; the estimate
      # stays honest at half a minute a card.
      def review_minutes = [ (reviews_due_count / 2.0).ceil, 1 ].max

      # The oversight surface (§8): subjects other household members chose
      # to share with the viewer — exactly what grants expose, nothing more.
      def shared_subjects
        @shared_subjects ||= Subject.visible_to(viewer).where.not(user: viewer)
          .includes(:user).recently_studied_first.group_by(&:user)
      end

      # The record drawer's headline numbers (D-learning-record).
      def minutes_this_year
        @minutes_this_year ||= viewer.study_logs.between(Date.current.beginning_of_year..Date.current).sum(:minutes)
      end

      def mastered_this_year
        @mastered_this_year ||= Topic.joins(:subject)
          .where(subjects: { user_id: viewer.id }, mastery: :mastered)
          .where(mastered_on: Date.current.beginning_of_year..Date.current).count
      end

      def suggested_subjects
        @suggested_subjects ||= viewer.suggestions.actionable
          .where(watcher_slug: "subject_scout").order(created_at: :desc).limit(3)
      end
    end
  end
end
