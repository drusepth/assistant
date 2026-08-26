# Claims the feeds a new hobby should have been carrying all along
# (D-hobby-feeds §4). Enqueued when a hobby is created — from the capture
# chips, the add tile, or an OPML import's folders — and after an import,
# which is the one place feeds arrive by the dozen.
#
# Takes lens ids rather than a lens so six folders-as-hobbies cost one job
# and one question per chunk of feeds, not six of each.
class MapFeedsJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(user, lens_ids)
    lenses = Section.where(id: lens_ids).to_a
    return if lenses.empty? # the hobby was removed again before this ran

    moved = Hobbies::MapFeeds.call(user, lenses)
    Turbo::StreamsChannel.broadcast_refresh_to(user, :reader) if moved.any?
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Nothing to undo: mapping only ever adds, so a failed round leaves the
    # feeds exactly where they were and the user can Re-file any of them.
    record_failure(e, user: user, context: { lens_ids: lens_ids })
  end
end
