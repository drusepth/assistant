require "rexml/document"

module Career
  # Normalizes the job scout's sources into Postings: Greenhouse and Lever
  # public board JSON, the USAJobs API, and plain RSS/Atom. Every parser is
  # forgiving — a malformed entry is dropped, never fatal — and the output
  # shape is identical regardless of source.
  module FeedParser
    Posting = Data.define(:title, :company, :location, :url, :posted_on) do
      def line
        [ title, company, location ].compact.join(" — ")
      end
    end

    MAX_PER_FEED = 40

    module_function

    def parse(kind, body, fallback_company: nil)
      postings =
        case kind
        when "greenhouse" then greenhouse(body, fallback_company)
        when "lever" then lever(body, fallback_company)
        when "usajobs" then usajobs(body)
        else rss(body, fallback_company)
        end
      postings.select { |posting| posting.title.present? && posting.url.present? }.first(MAX_PER_FEED)
    rescue JSON::ParserError, REXML::ParseException
      []
    end

    def greenhouse(body, company)
      Array(JSON.parse(body)["jobs"]).map do |job|
        Posting.new(
          title: job["title"].to_s.strip, company: company,
          location: job.dig("location", "name").presence,
          url: job["absolute_url"].to_s, posted_on: parse_date(job["updated_at"])
        )
      end
    end

    def lever(body, company)
      Array(JSON.parse(body)).map do |job|
        next unless job.is_a?(Hash)

        Posting.new(
          title: job["text"].to_s.strip, company: company,
          location: job.dig("categories", "location").presence,
          url: job["hostedUrl"].to_s,
          posted_on: job["createdAt"] ? Time.at(job["createdAt"].to_i / 1000).to_date : nil
        )
      end.compact
    end

    def usajobs(body)
      items = JSON.parse(body).dig("SearchResult", "SearchResultItems") || []
      items.map do |item|
        descriptor = item["MatchedObjectDescriptor"] || {}
        Posting.new(
          title: descriptor["PositionTitle"].to_s.strip,
          company: descriptor["OrganizationName"].presence,
          location: descriptor["PositionLocationDisplay"].presence,
          url: descriptor["PositionURI"].to_s, posted_on: parse_date(descriptor["PublicationStartDate"])
        )
      end
    end

    def rss(body, company)
      document = REXML::Document.new(body)
      items = REXML::XPath.match(document, "//item") # RSS
      items = REXML::XPath.match(document, "//entry") if items.empty? # Atom
      items.map do |item|
        link = item.elements["link"]
        url = link&.text.presence || link&.attributes&.[]("href")
        Posting.new(
          title: item.elements["title"]&.text.to_s.strip, company: company,
          location: nil, url: url.to_s.strip,
          posted_on: parse_date(item.elements["pubDate"]&.text || item.elements["updated"]&.text)
        )
      end
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
