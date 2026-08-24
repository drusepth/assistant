module Feeds
  # Fetch one feed and fold what's new into the river (D-feed-reader).
  # Idempotent by the entry's guid, so a publisher who re-publishes the same
  # item every hour (many do) can't flood the reader, and an item you have
  # already read stays read when its feed re-lists it.
  #
  # Existing rows are updated in place rather than replaced: a corrected
  # headline should reach a reader, but the *state* attached to the item —
  # read, saved — belongs to the reader and is never touched here.
  class Refresh
    Result = Data.define(:added, :updated, :error) do
      def ok? = error.nil?
      def changed? = added.positive? || updated.positive?
    end

    def self.call(feed, **options) = new(feed, **options).call

    # `keep` is an argument rather than a bare constant read so the pruning
    # can be exercised without inserting two hundred and fifty rows.
    def initialize(feed, keep: Feed::KEEP_PER_FEED)
      @feed = feed
      @keep = keep
    end

    def call
      page = Web::Fetch.raw(@feed.url, headers: request_headers)
      # The whole point of the conditional GET: the publisher said nothing
      # changed, so there is no body to parse and nothing to write beyond
      # "we checked".
      return unchanged(page) if page.not_modified?

      parsed = Parse.call(page.text)
      return failure("that address stopped being a feed") unless parsed

      added, updated = ingest(parsed)
      adopt_metadata(parsed)
      record_success(page, parsed)
      prune
      Result.new(added: added, updated: updated, error: nil)
    rescue Web::Fetch::Error => e
      failure(e.message)
    end

    private
      # Ask for what we haven't seen. A feed that hands back 304 costs its
      # publisher a header exchange and us no parse at all — the other half
      # of the politeness the interval floor starts (D-feed-reader).
      def request_headers
        { "Accept" => Discover::ACCEPT }.merge(@feed.conditional_headers)
      end

      def unchanged(page)
        record_success(page, nil)
        Result.new(added: 0, updated: 0, error: nil)
      end

      def record_success(page, parsed)
        @feed.record_success!(
          last_item_at: parsed&.entries&.filter_map(&:published_at)&.max,
          etag: page.headers["etag"], last_modified: page.headers["last-modified"]
        )
      end

      def ingest(parsed)
        added = updated = 0

        parsed.entries.each do |entry|
          item = @feed.feed_items.find_or_initialize_by(guid: entry.guid.to_s.truncate(500))
          item.assign_attributes(attributes_for(entry))
          next unless item.changed?

          item.new_record? ? added += 1 : updated += 1
          # One bad entry never costs a refresh the other forty.
          item.save or AppError.record(
            ActiveRecord::RecordInvalid.new(item), source: "Feeds::Refresh", user: @feed.user
          )
        end

        [ added, updated ]
      end

      def attributes_for(entry)
        {
          url: entry.url.presence&.truncate(2_000),
          title: entry.title.to_s.squish.truncate(300).presence || "(untitled)",
          author: entry.author&.squish&.truncate(120),
          summary: entry.summary,
          # A feed with no dates at all still has to sort: fall back to when
          # we first saw it, which is what "new to me" means anyway.
          published_at: entry.published_at || Time.current
        }
      end

      # The feed names itself; the user's own label always wins at display.
      def adopt_metadata(parsed)
        @feed.title = parsed.title if @feed.title.blank? && parsed.title.present?
        @feed.description = parsed.description if @feed.description.blank?
        @feed.site_url = parsed.site_url if @feed.site_url.blank? && parsed.site_url.present?
        @feed.kind = parsed.kind
      end

      # A river, not an archive: read items past the cap are dropped oldest
      # first. Saved items and unread items are never pruned — the first is
      # the user saying "keep this", the second is mail nobody has opened.
      def prune
        keepable = @feed.feed_items.read.where(saved_at: nil)
        excess = keepable.count - @keep
        return if excess <= 0

        # reorder, not order: the association sorts newest-first, and
        # appending to that would prune exactly the wrong end.
        doomed = keepable.reorder(Arel.sql("COALESCE(published_at, feed_items.created_at) ASC")).limit(excess)
        @feed.feed_items.where(id: doomed.pluck(:id)).delete_all
      end

      def failure(message)
        @feed.record_failure!(message)
        Result.new(added: 0, updated: 0, error: message)
      end
  end
end
