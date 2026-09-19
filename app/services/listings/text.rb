module Listings
  # The one text cleaner every listing parser goes through (D-listing-feeds):
  # markup to text, entities never expanded into markup, whitespace squished,
  # length capped — so nothing downstream holds a string it could be tempted
  # to mark safe.
  module Text
    MAX_DESCRIPTION = 2_000

    module_function

    def clean(value, limit: MAX_DESCRIPTION)
      text = value.to_s
      text = Nokogiri::HTML(text).text if text.include?("<")
      text.squish.truncate(limit).presence
    end

    # Only http(s) ever reaches an href.
    def http_url(value)
      value = value.to_s.strip
      value.match?(%r{\Ahttps?://\S+\z}i) ? value.truncate(2_000, omission: "") : nil
    end
  end
end
