class GenerateSubjectTreeJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(subject)
    profile = subject.generation_profile
    return unless profile
    return if subject.topics.any?

    Education::GenerateTree.new(subject: subject, profile: profile).build!
  rescue Llm::Error => e
    if will_retry?(e)
      @retrying = true
      raise
    end

    # Best-effort: out of chances, the subject is left an empty tree the
    # learner can fill by hand or retry from its page.
    record_failure(e, user: subject.user, context: { subject_id: subject.id })
  ensure
    # Stamp even on failure so "building your curriculum…" can't stick —
    # but not between retries, or the state would flicker per attempt.
    settle(subject) unless @retrying
  end

  private
    def settle(subject)
      return unless subject&.persisted?

      subject.update_column(:tree_built_at, Time.current)
      Turbo::StreamsChannel.broadcast_refresh_to(subject.user, :subjects)
    end
end
