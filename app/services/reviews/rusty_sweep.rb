module Reviews
  # The honest demotion (D-mastery-evidence): a mastered topic whose review
  # cards have decayed past the point of likely recall goes rusty — kept
  # history, terracotta notch, minutes to shore up. Deterministic
  # bookkeeping, not an agent action: FSRS predicts, the sweep records.
  class RustySweep
    # Below ~70% predicted recall the green tile would be a lie.
    RUSTY_BELOW = 0.7

    def self.run(user, now: Time.current)
      Topic.joins(:subject).where(subjects: { user_id: user.id }, mastery: :mastered)
        .where(id: ReviewItem.select(:topic_id))
        .includes(:review_items).find_each do |topic|
          decayed = topic.review_items.any? do |item|
            retention = Scheduler.retrievability(item, now: now)
            retention && retention < RUSTY_BELOW
          end
          topic.decay! if decayed
        end
    end
  end
end
