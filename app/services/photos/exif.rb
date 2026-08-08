module Photos
  # Deterministic EXIF reading for ingestion (D30): capture time and GPS out
  # of the original's metadata, via the libvips the variant pipeline already
  # depends on. Best-effort by design — a photo without (or with mangled)
  # EXIF is normal, so every parse failure is just "no value", never an error.
  class Exif
    Result = Struct.new(:taken_at, :latitude, :longitude)

    def self.read(path)
      new(Vips::Image.new_from_file(path.to_s)).result
    rescue StandardError
      Result.new(nil, nil, nil)
    end

    def initialize(image)
      @image = image
    end

    def result
      Result.new(taken_at, *coordinates)
    end

    private
      def taken_at
        raw = field("exif-ifd2-DateTimeOriginal") || field("exif-ifd0-DateTime")
        return nil unless raw

        Time.zone.strptime(raw[0, 19], "%Y:%m:%d %H:%M:%S")
      rescue ArgumentError
        nil
      end

      def coordinates
        latitude = coordinate("exif-ifd3-GPSLatitude", "exif-ifd3-GPSLatitudeRef", "S")
        longitude = coordinate("exif-ifd3-GPSLongitude", "exif-ifd3-GPSLongitudeRef", "W")
        latitude && longitude ? [ latitude, longitude ] : [ nil, nil ]
      end

      # GPS positions are three rationals — degrees, minutes, seconds — like
      # "40/1 44/1 5460/100", with the hemisphere in a separate Ref field.
      def coordinate(field_name, ref_name, negative_ref)
        raw = field(field_name)
        return nil unless raw

        degrees, minutes, seconds = raw.split(" ").first(3).map { |part| parse_rational(part) }
        return nil if degrees.nil?

        value = degrees + (minutes || 0) / 60.0 + (seconds || 0) / 3600.0
        field(ref_name)&.start_with?(negative_ref) ? -value.round(6) : value.round(6)
      end

      def parse_rational(part)
        numerator, denominator = part.split("/").map(&:to_f)
        return nil if numerator.nil? || denominator.nil? || denominator.zero?

        numerator / denominator
      end

      # libvips returns values with a trailing annotation — e.g.
      # "2019:07:04 16:20:00 (2019:07:04 16:20:00, ASCII, 20 components,
      # 20 bytes)" — which every parser here strips off.
      def field(name)
        return nil if @image.get_typeof(name).zero?

        @image.get(name).to_s.sub(/ \([^)]*\)\z/, "").presence
      end
  end
end
