module Feeds
  # One feed document in, normalized entries out (D-feed-reader). RSS 2.0,
  # RDF/RSS 1.0, Atom and JSON Feed all arrive here and leave in the same
  # shape, because the reader has no business knowing which dialect a
  # publisher chose.
  #
  # Forgiving on purpose, the FeedParser rule: one malformed entry is
  # dropped, never fatal — half the feeds on the open web are slightly
  # broken and a reader that refuses them is a reader nobody can use.
  # Namespaces are stripped rather than declared, since the prefixes are
  # not stable in the wild (`content:encoded`, `media:thumbnail` and
  # `dc:creator` all appear under invented prefixes).
  module Parse
    Entry = Data.define(:guid, :url, :title, :author, :summary, :image_url, :published_at)

    Result = Data.define(:kind, :title, :site_url, :description, :entries) do
      def feed? = title.present? || entries.any?
    end

    MAX_ENTRIES = 100
    MAX_SUMMARY = 2_000

    module_function

    # Returns a Result, or nil when the body isn't a feed at all — which is
    # how Discover tells "this URL is the feed" from "this URL is a page
    # that might link to one".
    def call(body)
      text = body.to_s
      return nil if text.strip.empty?

      result = text.lstrip.start_with?("{") ? json_feed(text) : xml_feed(text)
      result if result&.feed?
    end

    def json_feed(body)
      document = JSON.parse(body)
      return nil unless document.is_a?(Hash) && document["items"].is_a?(Array)

      entries = document["items"].filter_map { |item| json_entry(item) }
      Result.new(
        kind: "json", title: document["title"].to_s.squish.presence,
        site_url: document["home_page_url"].presence,
        description: document["description"].to_s.squish.presence,
        entries: entries.first(MAX_ENTRIES)
      )
    rescue JSON::ParserError
      nil
    end

    def xml_feed(body)
      # Recover from the small breakages half the feeds on the web ship
      # (a bare `&`, a stray tag), but never fetch a DTD or substitute an
      # entity: a feed is hostile input from a stranger's server.
      document = Nokogiri::XML(body.scrub) { |config| config.recover.nonet }
      document.remove_namespaces!
      root = document.root
      return nil unless root

      case root.name
      when "feed" then atom(root)
      when "rss", "RDF" then rss(root)
      end
    rescue Nokogiri::XML::SyntaxError
      nil
    end

    def rss(root)
      channel = root.at_xpath("./channel") || root
      entries = root.xpath(".//item").filter_map { |item| rss_entry(item) }
      Result.new(
        kind: "rss", title: text_of(channel.at_xpath("./title")),
        site_url: text_of(channel.at_xpath("./link")),
        description: text_of(channel.at_xpath("./description")),
        entries: entries.first(MAX_ENTRIES)
      )
    end

    def atom(root)
      entries = root.xpath("./entry").filter_map { |entry| atom_entry(entry) }
      Result.new(
        kind: "atom", title: text_of(root.at_xpath("./title")),
        site_url: atom_link(root),
        description: text_of(root.at_xpath("./subtitle")),
        entries: entries.first(MAX_ENTRIES)
      )
    end

    def rss_entry(item)
      # RSS 1.0 items carry their link in rdf:about when <link> is missing.
      url = text_of(item.at_xpath("./link")) || item["about"]
      title = text_of(item.at_xpath("./title"))
      guid = text_of(item.at_xpath("./guid")) || url || title
      return nil if title.blank? && url.blank?

      Entry.new(
        guid: guid, url: url, title: title.presence || url,
        author: text_of(item.at_xpath("./creator")) || text_of(item.at_xpath("./author")),
        summary: summarize(
          text_of(item.at_xpath("./description")) || text_of(item.at_xpath("./encoded"))
        ),
        image_url: image_in(item),
        published_at: parse_time(text_of(item.at_xpath("./pubDate")) || text_of(item.at_xpath("./date")))
      )
    end

    def atom_entry(entry)
      url = atom_link(entry)
      title = text_of(entry.at_xpath("./title"))
      guid = text_of(entry.at_xpath("./id")) || url || title
      return nil if title.blank? && url.blank?

      Entry.new(
        guid: guid, url: url, title: title.presence || url,
        author: text_of(entry.at_xpath("./author/name")),
        summary: summarize(
          text_of(entry.at_xpath("./summary")) || text_of(entry.at_xpath("./content"))
        ),
        image_url: image_in(entry),
        published_at: parse_time(
          text_of(entry.at_xpath("./published")) || text_of(entry.at_xpath("./updated"))
        )
      )
    end

    def json_entry(item)
      return nil unless item.is_a?(Hash)

      url = item["url"].presence || item["external_url"].presence
      title = item["title"].to_s.squish
      guid = item["id"].presence || url || title
      return nil if title.blank? && url.blank?

      Entry.new(
        guid: guid.to_s, url: url, title: title.presence || url,
        author: item.dig("author", "name").presence || Array(item["authors"]).first&.dig("name"),
        summary: summarize(item["summary"].presence || item["content_text"].presence || item["content_html"]),
        image_url: http_url(item["image"].presence || item["banner_image"]),
        published_at: parse_time(item["date_published"] || item["date_modified"])
      )
    end

    # An Atom link is addressed by its rel. Prefer the one that means "the
    # human-readable version of this", then a link that states no rel at
    # all, then whatever is left — `self` and `edit` links are the ones
    # this ordering exists to avoid handing to a reader.
    def atom_link(node)
      links = node.xpath("./link").select { |candidate| candidate["href"].present? }
      preferred = links.find { |link| link["rel"] == "alternate" } ||
        links.find { |link| link["rel"].blank? } || links.first
      preferred&.[]("href")
    end

    # Publishers put the picture in three different places and none of them
    # is a standard. Nothing renders it today (the river is text — see
    # docs/READER.md), but the guard lives here rather than at some future
    # call site: an entry that reaches anything downstream carries an
    # http(s) address or nothing at all.
    def image_in(node)
      enclosure = node.xpath("./enclosure").find { |tag| tag["type"].to_s.start_with?("image/") }
      thumbnail = node.at_xpath("./thumbnail") || node.at_xpath("./content[@medium='image']")
      found = enclosure&.[]("url") || thumbnail&.[]("url") ||
        node.at_xpath("./image")&.then { |image| image["href"] || text_of(image) }
      http_url(found)
    end

    def http_url(url)
      url.to_s.strip.match?(%r{\Ahttps?://\S+\z}i) ? url.to_s.strip : nil
    end

    def text_of(node)
      node&.text.to_s.squish.presence
    end

    # Feed summaries are HTML as often as not. The reader shows text — the
    # article itself is one click away — so the markup is stripped here
    # rather than sanitized at render time, and nothing downstream ever
    # holds a string it would be tempted to call `html_safe` on.
    def summarize(value)
      return nil if value.blank?

      Nokogiri::HTML(value.to_s).text.squish.presence&.truncate(MAX_SUMMARY)
    end

    def parse_time(value)
      return nil if value.blank?
      return value if value.is_a?(Time)

      Time.zone.parse(value.to_s) || Time.zone.at(DateTime.parse(value.to_s).to_time)
    rescue ArgumentError, TypeError, Date::Error
      nil
    end
  end
end
