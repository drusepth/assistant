module Radar
  # The rows the user already judged themselves (D-radar-accounts): an
  # event they said "maybe" to on their own account. Not a stranger's
  # calendar, so Radar::Match never reads them; not a commitment, so they
  # don't go on the calendar; a nudge inside the lead time, with or without
  # a model, because no judgment is being borrowed.
  #
  # A happening needs a place to be near. A saved row lands under the
  # user's place whose radius covers its coordinates when it carries any,
  # otherwise under their first place; with no places at all there is
  # nowhere to put it, and it is simply not recorded (the account card
  # says so).
  class Saved
    def self.record!(user, items, account:) = new(user, account).record!(items)

    def initialize(user, account)
      @user = user
      @account = account
    end

    # Returns the rows written or refreshed. Idempotent by uid.
    def record!(items)
      return [] if places.empty?

      now = Time.current
      rows = items.filter_map do |item|
        place = place_for(item) or next
        source = source_for(place)
        row = source.happenings.find_or_initialize_by(uid: item.uid)
        row.assign_attributes(
          provenance: "saved", kind: "event", title: item.title, description: item.description,
          location: item.location, url: item.url, latitude: item.latitude, longitude: item.longitude,
          starts_at: item.starts_at, ends_at: item.ends_at, all_day: item.all_day,
          series_uid: item.series_uid, withdrawn_at: nil, last_seen_at: now, matched_at: now,
          distance_mi: item.located? ? place.distance_to(item.latitude, item.longitude).round(1) : nil
        )
        row.save ? row : nil
      end
      withdraw_missing(rows, now)
      rows
    end

    private
      # Read fresh, not through a possibly-stale association: the account
      # sync runs against a user object that may have been around a while.
      def places = @places ||= Place.where(user: @user).order(:position, :id).to_a

      def place_for(item)
        return places.first unless item.located?

        places.find { |place| place.within?(item.latitude, item.longitude) } || places.first
      end

      # One account source per place, named for the account, never fetched.
      def source_for(place)
        place.listing_sources.find_or_create_by!(url: "https://#{host}/#{@account.provider}/saved") do |source|
          source.kind = "account"
          source.title = "Saved on #{@account.provider_label}"
        end
      end

      def host = @account.provider == "meetup" ? "www.meetup.com" : "www.eventbrite.com"

      # A saved row that the account no longer lists was un-saved: gone from
      # the river, and the watcher retires its nudge.
      def withdraw_missing(rows, now)
        Happening.where(listing_source_id: places.flat_map { |place| place.listing_sources.select { |s| s.kind == "account" && s.url.include?("/#{@account.provider}/") }.map(&:id) })
          .live.upcoming(now).where.not(id: rows.map(&:id))
          .update_all(withdrawn_at: now, updated_at: now)
      end
  end
end
