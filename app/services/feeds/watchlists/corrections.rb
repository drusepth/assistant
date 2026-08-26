module Feeds
  module Watchlists
    # What "Not this" teaches (D-story-matching §4.3).
    #
    # A rejection does three things, in order of how much they cost:
    #
    #   1. **tombstones the row.** The match keeps its record with a
    #      `rejected_at`, so the next backfill doesn't cheerfully bring the
    #      same story back — a correction that forgets itself is not a
    #      correction;
    #   2. **narrows the rule, deterministically.** A term whose stories the
    #      user keeps throwing away is not what this household means. No
    #      model call: counting is counting;
    #   3. **asks for a re-write, eventually.** Once corrections have piled
    #      up, `AuthorWatchlistJob` re-reads the whole rule with the
    #      rejections as examples — one call, after several corrections,
    #      never one per click.
    #
    # The one thing it deliberately does *not* do is add the fired term to
    # the negatives. A negative kills every story carrying that word, and
    # the word that fired is usually the right word inside the wrong story
    # — "warbler" in *Warbler Records signs a band*. Negating it would take
    # every real warbler story with it. Removing an over-broad term narrows
    # the rule; negating a good one guts it. Negatives stay a thing the user
    # types on purpose.
    module Corrections
      # How many of a rule's own matches to look at. A reader is a river:
      # the recent past is the only part that describes what it is doing now.
      SAMPLE = 500
      # One wrong story is a wrong story. Three is a wrong word.
      MIN_REJECTIONS = 3
      # Corrections since the last re-write that make asking worth a call.
      REAUTHOR_AFTER = 5

      module_function

      def reject!(match, user)
        match.reject!
        watchlist = Watchlist.find_by(user: user, section_id: match.section_id)
        return match unless watchlist

        drop_failing_terms(watchlist)
        request_reauthor(watchlist)
        match
      end

      def restore!(match) = match.update!(rejected_at: nil)

      # {term => {rejected:, kept:}} over this rule's recent matches. A
      # *kept* match is one the user read: opening the story is the only
      # confirmation a reader ever gives, and it is a real one.
      def tally(watchlist)
        rows = watchlist.matches.joins(:feed_item).order(id: :desc).limit(SAMPLE)
          .pluck(:terms, :rejected_at, "feed_items.read_at")

        rows.each_with_object(Hash.new { |hash, key| hash[key] = { rejected: 0, kept: 0 } }) do |(terms, rejected_at, read_at), counts|
          Array(terms).each do |term|
            next counts[term][:rejected] += 1 if rejected_at
            counts[term][:kept] += 1 if read_at
          end
        end
      end

      def drop_failing_terms(watchlist)
        failing = tally(watchlist).select do |term, count|
          watchlist.terms.include?(term) && count[:rejected] >= MIN_REJECTIONS && count[:rejected] > count[:kept]
        end
        return if failing.empty?

        watchlist.update!(
          terms: watchlist.terms - failing.keys,
          dropped: watchlist.dropped + failing.map { |term, count| dropped_row(term, count) }
        )
        # The rule narrowed, so its matches are re-derived from scratch —
        # tombstones and hand-filed rows survive the rebuild by design.
        MatchStoriesJob.perform_later(watchlist)
      end

      def dropped_row(term, count)
        { "term" => term, "kind" => "rejected",
          "detail" => "you turned down #{count[:rejected]} of the stories it found" }
      end

      def request_reauthor(watchlist)
        return unless watchlist.user.household.model_profile&.configured?
        return if rejections_since_authoring(watchlist) < REAUTHOR_AFTER

        AuthorWatchlistJob.perform_later(watchlist)
      end

      def rejections_since_authoring(watchlist)
        scope = watchlist.matches.rejected
        scope = scope.where(rejected_at: watchlist.authored_at..) if watchlist.authored_at
        scope.count
      end
    end
  end
end
