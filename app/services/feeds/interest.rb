module Feeds
  # What this user finds interesting, learned from what they already own
  # (D-feed-reader). Deterministic and model-free on purpose: the reader has
  # to work on a household instance with no API key configured at all, and
  # the ranking of somebody's own reading is not a good place for a rented
  # model to have opinions.
  #
  # Three sources of signal, all of them the user's own words:
  #
  #   * their hobby lenses — the names they chose for the things they do,
  #   * what they keep under those lenses — the titles of hobby-tagged
  #     notes, goals, tasks and events, which is the profile note idea from
  #     docs/HOBBIES.md §1 read as vocabulary rather than as prose,
  #   * the votes they cast in the reader — the only signal the reader
  #     itself creates, and the reason a river of the same five feeds gets
  #     more useful over a month instead of staying flat.
  #
  # Nothing here leaves the instance, and every weight is inspectable — the
  # "why am I seeing this" question has an answer made of the user's own
  # nouns.
  class Interest
    # A word has to earn a weight; these are the ones every feed on earth
    # contains. English-only, which is honest about where it helps: a
    # missing stop word costs a little precision, never correctness.
    STOP_WORDS = %w[
      the and for with from this that what when your you are was were will
      how why who all any our out new now get got has have had can could
      would should about into over under more most just like than then them
      they there their his her its it's one two three four five here
    ].to_set.freeze

    LENS_WEIGHT = 1.0
    OWNED_WEIGHT = 0.3
    UPVOTE_WEIGHT = 0.5
    # Dislike learns faster than like, because a river's failure mode is
    # one loud feed drowning the rest, and the user has already told us.
    DOWNVOTE_WEIGHT = -0.9

    OWNED_TITLES = 200
    VOTED_ITEMS = 200
    MIN_TOKEN = 3
    MAX_TOKEN = 32

    def self.for(user) = new(user)

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # -1.0 (they've told us they don't want this) to 1.0 (this is squarely
    # their thing). Squashed rather than summed so a headline that happens
    # to hit six weak words can't outrank one that hits the hobby itself.
    def score(text, sections: [])
      raw = raw_score(text, sections: sections)
      Math.tanh(raw / 2.0).round(4)
    end

    def raw_score(text, sections: [])
      words = self.class.tokenize(text)
      return 0.0 if words.empty?

      haystack = text.to_s.downcase
      # The feed's own lenses first: an item from the Guitar feed is about
      # guitar whatever its headline says, which is the whole reason
      # subscriptions are filed rather than items. Once, not once per lens —
      # a feed filed under three hobbies isn't three times as interesting.
      total = sections.any? ? LENS_WEIGHT : 0.0
      total += words.uniq.sum { |word| weights.fetch(word, 0.0) }
      # A multi-word hobby ("board games") appearing whole is worth more
      # than its words appearing apart.
      total += phrases.count { |phrase| haystack.include?(phrase) } * LENS_WEIGHT
      total
    end

    # token => weight, built once per instance. Small enough to hold in
    # memory by construction: a household's hobbies, two hundred item
    # titles, two hundred votes.
    def weights
      @weights ||= begin
        map = Hash.new(0.0)
        add(map, lens_names, LENS_WEIGHT)
        add(map, owned_titles, OWNED_WEIGHT)
        add(map, voted_titles(FeedItem::UP), UPVOTE_WEIGHT)
        add(map, voted_titles(FeedItem::DOWN), DOWNVOTE_WEIGHT)
        map
      end
    end

    # The multi-word lens names, lowercased, for the phrase bonus.
    def phrases
      @phrases ||= lens_names.map { |name| name.downcase.squish }.select { |name| name.include?(" ") }
    end

    # The strongest words behind a score, for the reader's "why this is
    # here" line. Explanation is a feature: an unexplainable feed is the
    # thing this whole section exists to be an alternative to.
    def reasons(text, sections: [], limit: 3)
      lenses = sections.map { |section| section.name }
      hits = self.class.tokenize(text).uniq
        .filter_map { |word| [ word, weights[word] ] if weights[word].to_f.positive? }
        .sort_by { |_word, weight| -weight }.first(limit).map(&:first)
      (lenses + hits).uniq.first(limit)
    end

    # Re-score a feed's items after its lenses change — filing a feed under
    # a hobby has to be visible in the river immediately, not after the
    # next fetch.
    def rescore!(feed)
      sections = feed.sections.to_a
      feed.feed_items.recent.find_each do |item|
        item.update_column(:relevance, score(item.text_for_matching, sections: sections))
      end
    end

    def self.tokenize(text)
      text.to_s.downcase.scan(/[a-z][a-z0-9'+-]*/)
        .map { |word| word.delete_suffix("'s") }
        .select { |word| word.length.between?(MIN_TOKEN, MAX_TOKEN) && !STOP_WORDS.include?(word) }
    end

    private
      def add(map, strings, weight)
        strings.each do |string|
          self.class.tokenize(string).uniq.each { |word| map[word] += weight }
        end
      end

      # The hobby lenses themselves (D25) — one query, both uses.
      def lenses
        @lenses ||= Section.find_by(slug: "hobbies")&.children&.to_a || []
      end

      def lens_names = lenses.map(&:name)

      # What the user keeps under those lenses. Titles only: a note's body
      # is long enough to swamp every other signal, and the title is where
      # people put the nouns anyway.
      def owned_titles
        @owned_titles ||= [
          user.notes.where(id: tagged_ids("Note")).order(updated_at: :desc).limit(OWNED_TITLES).pluck(:title),
          user.goals.where(id: tagged_ids("Goal")).order(created_at: :desc).limit(OWNED_TITLES).pluck(:title),
          user.tasks.where(id: tagged_ids("Task")).order(created_at: :desc).limit(OWNED_TITLES).pluck(:title),
          user.events.where(id: tagged_ids("Event")).order(starts_at: :desc).limit(OWNED_TITLES).pluck(:title)
        ].flatten.compact
      end

      # Taggings are polymorphic, so the type is half the key: without it a
      # Note and a Task that happen to share an id would tag each other.
      def tagged_ids(type)
        SectionTagging.where(section_id: lenses.map(&:id), taggable_type: type).select(:taggable_id)
      end

      def voted_titles(direction)
        user.feed_items.where(vote: direction).order(updated_at: :desc)
          .limit(VOTED_ITEMS).pluck(:title)
      end
  end
end
