module Listings
  # What every listing parser emits, whatever the source's format
  # (D-listing-feeds) — the shape `Listings::Refresh` folds into happenings.
  # All text is plain by the time it is here (Listings::Text): a parser
  # strips markup and refuses non-http links.
  Item = Data.define(
    :uid, :series_uid, :kind, :title, :description, :location, :url,
    :latitude, :longitude, :starts_at, :ends_at, :all_day, :expires_on
  ) do
    def self.build(uid:, title:, kind: "event", series_uid: nil, description: nil, location: nil, url: nil,
                   latitude: nil, longitude: nil, starts_at: nil, ends_at: nil, all_day: false, expires_on: nil)
      new(
        uid: uid, series_uid: series_uid || uid, kind: kind, title: title,
        description: description, location: location, url: url,
        latitude: latitude, longitude: longitude,
        starts_at: starts_at, ends_at: ends_at, all_day: all_day, expires_on: expires_on
      )
    end

    def located? = latitude.present? && longitude.present?
    def opening? = kind == "opening"
  end
end
