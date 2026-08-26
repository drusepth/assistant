module Feeds
  module Watchlists
    # What may become a term (D-story-matching §3.1). Everything that enters
    # a watchlist comes through here — hand-typed, model-authored, or
    # imported — so there is exactly one answer to "what is a term".
    #
    # A term is a **word or short phrase**. Never a pattern: no regex
    # metacharacters survive, so nothing a model writes and nothing copied
    # out of a stranger's feed can become a regular expression, a query, or
    # anything but a string compared against a title.
    module Terms
      MIN_LENGTH = 3
      MAX_LENGTH = 40
      MAX_WORDS = 4

      # Words that would match half of everything. They are dropped rather
      # than tested against the corpus, because they are wrong on every
      # instance and nobody should have to see them proposed.
      STOPWORDS = %w[
        the a an and or of for in on at to with from new news best top guide
        how why what when who is are was this that it its your you our we
        post posts article blog update updates story stories week weekly day
        daily list review reviews video videos podcast episode
      ].to_set.freeze

      module_function

      # Case-folded, accent-folded, punctuation-stripped, whitespace-squished
      # — the one normalization both a term and a story title pass through,
      # so "Crème brûlée" in a headline meets "creme brulee" in a list.
      #
      # NFKD-then-strip-marks rather than transliteration: transliterating
      # non-Latin text turns Japanese into question marks, and a household
      # reading Japanese feeds is exactly as entitled to this feature.
      def fold(text)
        text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "")
          .downcase.gsub(/[^[:alnum:][:space:]'-]/, " ").squish
      rescue ArgumentError, Encoding::CompatibilityError
        # Broken encoding out of a stranger's XML is not a crash.
        text.to_s.scrub("").downcase.squish
      end

      def clean(list)
        Array(list).filter_map { |term| normalize(term) }.uniq.reject { |term| STOPWORDS.include?(term) }
      end

      def normalize(term)
        # A term is a word. A model that answers with an object answered
        # the wrong question, and `to_s` on it would smuggle its punctuation
        # into somebody's list.
        return nil unless term.is_a?(String) || term.is_a?(Symbol)

        folded = fold(term)
        return nil if folded.blank? || folded.length > MAX_LENGTH
        return nil if folded.split.size > MAX_WORDS
        return nil if folded.length < MIN_LENGTH && ascii_word?(folded)

        folded
      end

      # A two-letter term is too broad in English and perfectly ordinary in
      # scripts that don't space their words.
      def ascii_word?(term) = term.match?(/[a-z0-9]/)

      # Word-boundary matching where words have boundaries, substring
      # matching where they don't (CJK), because `\b` between two kanji is
      # not a place.
      def pattern(term)
        escaped = Regexp.escape(term)
        ascii_word?(term) ? /(?<![[:alnum:]])#{escaped}(?![[:alnum:]])/ : /#{escaped}/
      end
    end
  end
end
