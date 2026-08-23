require "csv"

module Datasets
  # The gazetteer behind the photo map's place names (docs/TRAVEL.md §2):
  # ~7,300 public-domain settlements, read from a local file, nearest-match
  # in memory. No lookup service and no model — a reverse-geocoder's request
  # log for a photo library is the owner's itinerary, and a model asked to
  # name a coordinate will happily invent a confident wrong answer.
  #
  # What it can honestly say is bounded by what it holds. A gazetteer of
  # cities can tell you a photo was taken *near* somewhere it knows; it
  # cannot tell you the neighbourhood, and it has never heard of the village
  # you stayed in. So a match carries its distance, and the label says
  # "Lisbon" only when the coordinates really are Lisbon — otherwise "Near
  # Lisbon", and beyond 100km, nothing at all.
  class Places
    FILENAME = "places.csv".freeze
    META_FILENAME = "places.yml".freeze
    # Also the shape the admin import validates against, so a denser
    # gazetteer can be dropped in without a release.
    HEADERS = %w[ name country latitude longitude population ].freeze

    # Close enough to be the place; close enough to be worth naming; beyond
    # that, silence.
    EXACT_KM = 20.0
    NEAR_KM = 100.0

    EARTH_RADIUS_KM = 6371.0
    KM_PER_DEGREE = 111.32

    Match = Data.define(:name, :country, :latitude, :longitude, :population, :distance_km) do
      def near? = distance_km > EXACT_KM
      def label = near? ? "Near #{name}" : name
      def qualified = "#{label}, #{country}"
    end

    # Memoized: the file is a few hundred KB and never changes between
    # requests, so parsing it per lookup would be the map's slowest step by
    # a wide margin.
    def self.current = @current ||= new
    def self.reset! = @current = nil

    def initialize(path: Datasets.read_path(FILENAME))
      @bands = build_index(path)
      @size = @bands.values.sum(&:size)
    end

    def present? = @size.positive?
    def size = @size

    # The nearest settlement within NEAR_KM, or nil when the coordinates are
    # somewhere this file has never heard of — an ocean, a desert, most of
    # Greenland. Ties break by population: of two equally close entries the
    # one people have heard of is the better answer.
    def nearest(latitude, longitude)
      return nil unless present?

      best = nil
      candidates(latitude, longitude).each do |row|
        distance = haversine(latitude, longitude, row[:latitude], row[:longitude])
        next if distance > NEAR_KM
        next if best && (distance > best[:distance] ||
          (distance == best[:distance] && row[:population] <= best[:row][:population]))

        best = { row: row, distance: distance }
      end
      return nil unless best

      Match.new(**best[:row].slice(:name, :country, :latitude, :longitude, :population),
        distance_km: best[:distance].round(1))
    end

    private
      # One-degree latitude bands. A band is 111km tall, so scanning the
      # photo's band and its two neighbours always covers at least ±1°,
      # which is more than NEAR_KM — no candidate inside the radius can hide
      # in a band we skipped. Longitude is deliberately not bucketed: a band
      # holds every longitude, so the antimeridian needs no special case.
      def candidates(latitude, longitude)
        band = latitude.floor
        rows = (band - 1..band + 1).flat_map { |index| @bands[index] || [] }
        return rows if rows.empty?

        # Longitude degrees shrink towards the poles, so the window that can
        # hold a 100km match is narrow near London and enormous near
        # Svalbard. Computing it beats running haversine over a whole band.
        window = NEAR_KM / (KM_PER_DEGREE * Math.cos(to_radians(latitude)).abs).clamp(0.001, Float::INFINITY)
        return rows if window >= 180

        rows.select { |row| longitude_delta(longitude, row[:longitude]) <= window }
      end

      def longitude_delta(one, two)
        delta = (one - two).abs
        delta > 180 ? 360 - delta : delta
      end

      def haversine(lat1, lon1, lat2, lon2)
        d_lat = to_radians(lat2 - lat1)
        d_lon = to_radians(lon2 - lon1)
        a = (Math.sin(d_lat / 2)**2) +
          (Math.cos(to_radians(lat1)) * Math.cos(to_radians(lat2)) * (Math.sin(d_lon / 2)**2))
        2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a).clamp(0.0, 1.0))
      end

      def to_radians(degrees) = degrees * Math::PI / 180.0

      # A missing or malformed gazetteer is an unnamed map, never an error:
      # every caller already handles "this pin has no name".
      def build_index(path)
        return {} unless path

        CSV.read(path, headers: true, encoding: "UTF-8").each_with_object({}) do |row, bands|
          latitude = Float(row["latitude"], exception: false)
          longitude = Float(row["longitude"], exception: false)
          next unless latitude && longitude && row["name"].present?

          (bands[latitude.floor] ||= []) << {
            name: row["name"], country: row["country"].to_s,
            latitude: latitude, longitude: longitude, population: row["population"].to_i
          }
        end
      rescue CSV::MalformedCSVError, SystemCallError
        {}
      end
  end
end
