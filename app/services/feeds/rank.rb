module Feeds
  # The river's "Interesting" order (D-feed-reader) — the reddit-shaped half
  # of the ask, with the part that makes those feeds hostile left out.
  #
  # Two inputs and nothing else: how new an item is, and how well it matches
  # what this user is into (Interest, computed at ingest and stored on the
  # row). No engagement optimisation, no dwell time, no "people like you",
  # and no ordering the user can't turn off — "Newest" is one click away and
  # every source is one they chose.
  #
  #   score = relevance × BOOST_HOURS − hours_old  (+ a little, if saved)
  #
  # Everything is in hours, which is what makes the ranking explainable in
  # one sentence: **a perfect match is worth half a day of freshness.** A
  # strong match leads the river this morning and is behind this afternoon's
  # news by tonight — a lift, never a permanent seat, which is the failure
  # mode of every feed that ranks purely on affinity. relevance is -1..1, so
  # an item made of words the user downvoted is pushed *down* by the same
  # half day rather than being hidden: the reader never silently disappears
  # a source somebody subscribed to.
  module Rank
    BOOST_HOURS = 12.0
    SAVED_BONUS_HOURS = 3.0

    module_function

    def score(item, now: Time.current)
      # Future-dated items are common (scheduled posts, bad clocks) and must
      # not out-rank the entire river: the newest an item can be is "now".
      hours = [ (now - item.published_on) / 1.hour, 0.0 ].max
      relevance = item.relevance.to_f.clamp(-1.0, 1.0)
      (relevance * BOOST_HOURS) - hours + (item.saved? ? SAVED_BONUS_HOURS : 0.0)
    end

    # Stable: ties break by recency, so two items with identical scores
    # don't shuffle between page loads.
    def sort(items, now: Time.current)
      items.sort_by { |item| [ -score(item, now: now), -item.published_on.to_i, -item.id ] }
    end
  end
end
