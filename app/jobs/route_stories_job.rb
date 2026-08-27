# Reads the stories a broad feed just delivered and files the ones that are
# about the user's hobbies (D-story-matching).
#
# In a job rather than the refresh, for the reason every model call in the
# reader is: a publisher's poll must not wait on a provider, and the story
# is already in the river — routing only decides which *other* river it
# also appears in.
#
# It is idempotent and self-limiting: `routed_at` marks a story read by the
# router whether or not anything came of it, so two runs racing each other
# find nothing to do rather than double-reading a batch.
class RouteStoriesJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(user)
    Feeds::RouteStories.call(user)
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Out of chances leaves the stories unrouted, which is what they were:
    # they stay in their own feed's river and the next run tries again.
    record_failure(e, user: user)
  end
end
