# Files one feed under the hobbies it belongs to (D-hobby-feeds).
#
# A job rather than the request, on purpose. Adding a feed *fetches* in the
# request because the user needs to know the subscription is real; a model
# call has no such claim on their patience and a slow provider must not hold
# the form. So the feed appears immediately — under the catch-all, which is
# where everything unfiled lives — and re-files itself over Turbo when this
# lands.
class ClassifyFeedJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(feed)
    return if feed.sections.any? # filed by hand while this waited its turn

    result = Feeds::Classify.call(feed)
    return file_as_other(feed) if result.nil? # nothing to ask, or nobody to ask

    # An empty answer is an answer: most feeds on the open web are not about
    # anybody's hobby, and saying so is what the catch-all is for.
    feed.sections = result.sections.presence || [ Hobbies::OtherInterests.find_or_create! ]
    feed.update!(classified_at: Time.current)
    broadcast(feed)
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Once the model is out of chances the feed is still a feed: it lands in
    # the catch-all like any unclassified subscription, `classified_at` stays
    # blank so a later "Re-file" can try again, and the user can file it by
    # hand from /feeds meanwhile.
    file_as_other(feed)
    record_failure(e, user: feed.user, context: { feed_id: feed.id })
  end

  private
    def file_as_other(feed)
      broadcast(feed) if Hobbies::OtherInterests.absorb!([ feed ]).any?
    end

    def broadcast(feed)
      Turbo::StreamsChannel.broadcast_refresh_to(feed.user, :reader)
    end
end
