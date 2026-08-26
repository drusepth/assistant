module Feeds
  module Watchlists
    # A rule is tested against the river before it ships (D-story-matching
    # §4.1).
    #
    # The failure a watchlist can actually have is not a wrong word, it is a
    # *broad* one: "nature" in a Birding list quietly turns the hobby into a
    # second copy of the news. No model can be trusted to know which words
    # are broad, because broadness isn't a property of the word — it is a
    # property of the feeds this household happens to follow. So every
    # candidate term is run against the last few hundred stories the user
    # actually has, and anything matching too many of them is dropped before
    # the rule is saved, with the number shown in the editor.
    #
    # It is the cheapest possible evaluation harness, and it runs on the
    # only corpus that matters.
    class Corpus
      SAMPLE = 500
      # Above this share of the user's own river, a term is describing the
      # river rather than the hobby.
      CEILING = 0.20
      # Under this much material the test can't say anything; a brand-new
      # instance shouldn't have its first rule gutted by three stories.
      MIN_ITEMS = 40

      Verdict = Data.define(:kept, :dropped)

      def initialize(user, sample: SAMPLE)
        @user = user
        @sample = sample
      end

      def enough? = texts.size >= MIN_ITEMS

      # Verdict(kept: [term], dropped: [{term:, share:}]) — order preserved,
      # because the model was asked for its best first.
      def test(terms)
        return Verdict.new(kept: terms, dropped: []) unless enough?

        kept = []
        dropped = []

        terms.each do |term|
          share = share_of(term)
          share > CEILING ? dropped << dropped_row(term, share) : kept << term
        end

        Verdict.new(kept: kept, dropped: dropped)
      end

      def share_of(term)
        pattern = Terms.pattern(term)
        texts.count { |text| pattern.match?(text) }.fdiv(texts.size)
      end

      private
        # Titles and the opening of each summary, folded once — the same
        # normalization the matcher itself uses, or the test would be
        # measuring a different rule than the one that will run.
        def texts
          @texts ||= @user.feed_items.newest.limit(@sample).pluck(:title, :summary)
            .map { |title, summary| Terms.fold("#{title} #{summary.to_s.truncate(Match::BODY_LIMIT)}") }
        end

        def dropped_row(term, share)
          { "term" => term, "kind" => "broad",
            "detail" => "it matched #{(share * 100).round}% of your river" }
        end
    end
  end
end
