# Writes (or re-writes) the words that mean a hobby (D-story-matching §4.2).
#
# In a job rather than the request, for the reason every model call in the
# reader is: naming a hobby must not wait on a provider. The lens, its page
# and its editor exist the moment the user hits Add — the words arrive when
# they arrive, and can be typed in by hand meanwhile.
class AuthorWatchlistJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(watchlist)
    Feeds::Watchlists::Author.call(watchlist)
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Out of chances is not a broken hobby: the rule stays whatever it was
    # (usually empty), the editor still works, and the user can ask again
    # from the hobby's own page.
    record_failure(e, user: watchlist.user, context: { watchlist_id: watchlist.id })
  end
end
