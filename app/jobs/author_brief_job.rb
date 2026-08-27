# Writes the sentence that says what a hobby means (D-story-matching §4).
#
# In a job rather than the request, for the reason every model call in the
# reader is: naming a hobby must not wait on a provider. The lens, its page
# and the box the user can type their own sentence into all exist the moment
# they hit Add.
class AuthorBriefJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(brief)
    Feeds::Briefs::Author.call(brief)
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Out of chances is not a broken hobby: the routing still works from the
    # hobby's name, and the user can write the sentence themselves.
    record_failure(e, user: brief.user, context: { brief_id: brief.id })
  end
end
