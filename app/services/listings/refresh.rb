module Listings
  # Fetch one listing source and fold what it publishes into happenings
  # (D-listing-feeds). Idempotent by uid, so a re-listed happening keeps
  # its matches, its hidden state and its link to the event you made; a
  # corrected time or title updates in place.
  #
  # Two things a feed refresh doesn't do. **Near is decided here**: a row
  # carrying its own coordinates gets its distance from the place, and one
  # beyond the radius is kept but marked out of range — hidden from the
  # river, never matched, visible under a fold so a wrong radius is
  # diagnosable. **Withdrawal is decided here**: an upcoming row the source
  # no longer lists was cancelled (or, for an opening, filled), and the
  # watcher retires anything built on it.
  class Refresh
    Result = Data.define(:added, :updated, :withdrawn, :error) do
      def ok? = error.nil?
      def changed? = added.positive? || updated.positive? || withdrawn.positive?
    end

    def self.call(source, **options) = new(source, **options).call

    def initialize(source, now: Time.current)
      @source = source
      @place = source.place
      @now = now
    end

    def call
      return Result.new(added: 0, updated: 0, withdrawn: 0, error: nil) unless @source.fetched?
      return ask_provider if @source.provider?

      page = Web::Fetch.raw(@source.url, headers: request_headers, max_bytes: Discover::MAX_BYTES)
      return unchanged(page) if page.not_modified?

      items = parse(page.text)
      return failure("that address stopped being a calendar") unless items

      fold(items, page)
    rescue Web::Fetch::Error => e
      failure(e.message)
    end

    private
      # A provider answers a query about the place rather than serving a
      # document, so there are no validators to echo — the interval is the
      # whole politeness.
      def ask_provider
        service = @source.provider_service or return failure("unknown provider #{@source.provider}")
        fold(service.call(@source), nil)
      end

      def fold(items, page)
        added, updated, seen = ingest(items)
        withdrawn = withdraw_missing(seen)
        record_success(page, added)
        prune
        Result.new(added: added, updated: updated, withdrawn: withdrawn, error: nil)
      end

      def request_headers
        { "Accept" => Discover::ACCEPT }.merge(@source.conditional_headers)
      end

      def parse(body)
        case @source.kind
        when "ics" then Parse::Ics.call(body)
        when "page" then Parse::Schema.call(body)
        end
      end

      def unchanged(page)
        record_success(page, 0)
        Result.new(added: 0, updated: 0, withdrawn: 0, error: nil)
      end

      def record_success(page, added)
        @source.record_success!(
          new_items: added, etag: page&.headers&.dig("etag"), last_modified: page&.headers&.dig("last-modified")
        )
      end

      def ingest(items)
        added = updated = 0
        seen = []

        items.each do |item|
          row = @source.happenings.find_or_initialize_by(uid: item.uid)
          row.assign_attributes(attributes_for(item))
          row.last_seen_at = @now
          # State attached to the row — hidden, matched, linked — belongs to
          # the user and is never touched here.
          if row.new_record?
            added += 1
          elsif (row.changed - %w[ last_seen_at ]).any?
            updated += 1
          end
          # One bad row never costs a refresh the other forty.
          row.save or AppError.record(
            ActiveRecord::RecordInvalid.new(row), source: "Listings::Refresh", user: @place.user
          )
          seen << row.id if row.persisted?
        end

        [ added, updated, seen ]
      end

      def attributes_for(item)
        attrs = {
          kind: item.kind, title: item.title, description: item.description, location: item.location,
          url: item.url, latitude: item.latitude, longitude: item.longitude,
          starts_at: item.starts_at, ends_at: item.ends_at, all_day: item.all_day,
          expires_on: item.expires_on, series_uid: item.series_uid, withdrawn_at: nil
        }
        attrs.merge(range_for(item))
      end

      # By construction, then by arithmetic: a row from a source attached to
      # Tulsa is in Tulsa unless it says otherwise.
      def range_for(item)
        return { distance_mi: nil, out_of_range: false } unless item.located?

        distance = @place.distance_to(item.latitude, item.longitude).round(1)
        { distance_mi: distance, out_of_range: distance > @place.radius_mi }
      end

      # An upcoming row the source stopped listing is gone from the world:
      # cancelled, or a role that was filled. Past rows going missing is the
      # ordinary shape of a calendar window and means nothing.
      def withdraw_missing(seen)
        @source.happenings.live.upcoming(@now).where.not(id: seen)
          .update_all(withdrawn_at: @now, updated_at: @now)
      end

      # A river, not an archive. What the user kept is kept with it.
      def prune
        cutoff = @now - Happening::PRUNE_AFTER
        doomed = @source.happenings.unlinked
          .where("COALESCE(happenings.ends_at, happenings.starts_at) < ?", cutoff)
          .or(@source.happenings.unlinked.where(kind: "opening").where("happenings.withdrawn_at < ? OR happenings.expires_on < ?", cutoff, cutoff.to_date))
        doomed.delete_all
      end

      def failure(message)
        @source.record_failure!(message)
        Result.new(added: 0, updated: 0, withdrawn: 0, error: message)
      end
  end
end
