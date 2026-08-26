module Feeds
  # The rule, applied (D-story-matching §3.2). One story against one
  # watchlist, in plain Ruby: no model, no network, no index, no cost. It
  # runs at ingest over the items a refresh just wrote, and in a backfill
  # when a rule changes.
  #
  # The rule is one sentence, and it is the same sentence the editor shows
  # the user: **a term in the title, or two distinct terms anywhere in title
  # and summary — and no negative anywhere.** A title hit alone is enough
  # because a headline is what the publisher chose to say the story is
  # about; two hits are asked of the body because prose mentions things in
  # passing and a headline doesn't.
  #
  # Two rules it never breaks:
  #
  #   - **a match never moves a feed.** Filing feeds is D-hobby-feeds' job
  #     and this cannot touch it;
  #   - **a match never overwrites a human.** An item/section pair that
  #     already has a row — matched, hand-filed, or rejected — is left
  #     exactly as it is, which is also how a rejection stays rejected.
  class Match
    # Enough to say why the row is here; the rest is noise on a hover.
    MAX_RECORDED_TERMS = 4
    # Prose is where a passing mention lives, and a very long body is where
    # a coincidence lives. Both are answered by reading the top of it.
    BODY_LIMIT = 2_000

    Rule = Struct.new(:watchlist, :section_id, :terms, :negatives) do
      def self.build(watchlist)
        new(watchlist, watchlist.section_id,
            watchlist.terms.to_h { |term| [ term, Watchlists::Terms.pattern(term) ] },
            watchlist.negatives.map { |term| Watchlists::Terms.pattern(term) })
      end

      # The terms that fired, or [] for no match.
      def hits(title, body)
        text = "#{title} #{body}"
        return [] if negatives.any? { |pattern| pattern.match?(text) }

        fired = terms.select { |_term, pattern| pattern.match?(text) }.keys
        return [] if fired.empty?

        in_title = fired.any? { |term| terms[term].match?(title) }
        return [] unless in_title || fired.size >= 2

        fired.first(MAX_RECORDED_TERMS)
      end
    end

    def self.for_feed(feed, items) = new(feed.user).call(feed, items)

    def initialize(user, watchlists: nil)
      @user = user
      @rules = (watchlists || Watchlist.where(user: user).with_terms.includes(:section))
        .map { |watchlist| Rule.build(watchlist) }
    end

    def any_rules? = @rules.any?

    # Returns the matches written. Rules whose hobby the feed already
    # carries are skipped — that item is in that river already, and a
    # second row saying so would be a duplicate the query has to dedupe.
    def call(feed, items)
      items = Array(items).reject(&:new_record?)
      rules = applicable(feed)
      return [] if rules.empty? || items.empty?

      existing = pairs_for(items)

      created = items.flat_map { |item| match_item(item, rules, existing) }
      guard(feed, created)
      created
    end

    private
      # A rule that has started matching most of what one feed publishes is
      # not describing the hobby any more (D-story-matching §6). Checked
      # per feed, after the writes, so the measurement includes what just
      # landed.
      def guard(feed, created)
        created.group_by(&:section_id).each do |section_id, matches|
          rule = @rules.find { |candidate| candidate.section_id == section_id }
          Watchlists::Flood.check(feed, rule.watchlist, matches) if rule
        end
      end

      def applicable(feed)
        carried = feed.section_ids
        @rules.reject { |rule| carried.include?(rule.section_id) || rule.watchlist.suspended_for?(feed) }
      end

      def match_item(item, rules, existing)
        title = Watchlists::Terms.fold(item.title)
        body = Watchlists::Terms.fold(item.summary.to_s.truncate(BODY_LIMIT))

        rules.filter_map do |rule|
          next if existing.include?([ item.id, rule.section_id ])

          hits = rule.hits(title, body)
          next if hits.empty?

          write(item, rule, hits)
        end
      end

      # Two writers can meet on the same story (a refresh and a backfill),
      # and losing that race means the row already exists — which is the
      # outcome either way.
      def write(item, rule, hits)
        FeedItemMatch.create!(feed_item_id: item.id, section_id: rule.section_id, terms: hits)
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      # One query for the whole batch: which item/section pairs already have
      # a row of any kind.
      def pairs_for(items)
        FeedItemMatch.where(feed_item_id: items.map(&:id)).pluck(:feed_item_id, :section_id).to_set
      end
  end
end
