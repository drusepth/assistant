class PersonalizeSubjectJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(subject)
    profile = subject.generation_profile
    return unless profile
    return if subject.interest_frame.blank?

    Education::PersonalizeTree.new(subject: subject, profile: profile).apply!
    Turbo::StreamsChannel.broadcast_refresh_to(subject.user, :subjects)
  rescue Llm::Error => e
    if will_retry?(e)
      raise
    end

    # Cosmetic pass: out of chances, the commons' own summaries stand.
    record_failure(e, user: subject.user, context: { subject_id: subject.id })
  end
end
