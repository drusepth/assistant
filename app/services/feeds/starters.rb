module Feeds
  # The empty state's stocked shelf (D-hobby-feeds §7.1).
  #
  # A reader whose empty state is a blank paste field asks the user to
  # already know what RSS is, which is most of why the format feels like a
  # hobbyist's. So: a short, hand-curated list of long-lived, publisher-run
  # feeds — **offered, never subscribed**. Nothing is followed at signup or
  # in the FTUE; every row is a checkbox somebody ticks, which is the line
  # READER.md's first promise draws (no recommendations from strangers, no
  # discovery feed — this is a shelf, not an engine).
  #
  # The list is `config/starter_feeds.opml`: static, offline, in the repo,
  # and editable or deletable by a self-hoster. Ticked rows go through
  # Feeds::Opml.import, which already skips fetching, matches folders to
  # existing hobby lenses by name, dedupes by URL and enqueues the refresh —
  # so this adds no fetch posture and no parse path of its own.
  module Starters
    PATH = Rails.root.join("config", "starter_feeds.opml")

    # `site` is the publisher's own page rather than the feed: Explore links
    # a row's name at it, because "what am I agreeing to read?" is a fair
    # question and raw XML is not an answer to it.
    Entry = Data.define(:url, :title, :folder, :site) do
      def host
        URI.parse(url.to_s).host.to_s.delete_prefix("www.")
      rescue URI::InvalidURIError
        ""
      end

      # What a search matches a row against, defined once so Explore's
      # server-side filter and its instant one can't drift apart — and
      # deliberately only what the row *shows*, since a filter that searches
      # invisible text looks broken from both directions.
      def haystack = "#{title} #{folder} #{host}".downcase
    end

    module_function

    def path = PATH

    # Grouped by folder, in file order — the folders are hobby names, which
    # is what lets an import file them on the way in.
    def groups
      entries.group_by(&:folder)
    end

    def entries
      @entries ||= Opml.entries(document).map do |entry|
        Entry.new(url: entry[:url], title: entry[:label].presence || entry[:url],
          folder: entry[:folder], site: entry[:site])
      end
    end

    # Only worth offering what the user isn't already following.
    def unfollowed_for(user)
      followed = user.feeds.pluck(:url).to_set
      entries.reject { |entry| followed.include?(entry.url) }
    end

    # The ticked subset, imported through the ordinary OPML path by handing
    # it a document containing exactly those rows: one code path for "a file
    # somebody exported" and "a shelf we shipped", which is the reason this
    # is OPML in the first place.
    #
    # `create_lenses:` is the one thing this passes through, and it defaults
    # to on here where the OPML importer defaults it off. The difference is
    # who chose the folders: an exported file's thirty folders are somebody
    # else's filing system, while a group ticked on this shelf *is* the
    # user saying "I'm interested in cooking" — which is what a hobby is.
    def import(user, urls, create_lenses: true)
      wanted = entries.select { |entry| urls.include?(entry.url) }
      return Opml::Result.new(added: 0, skipped: 0, lenses: [], error: nil) if wanted.empty?

      Opml.import(user, opml_for(wanted), create_lenses: create_lenses)
    end

    def opml_for(wanted)
      builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.opml(version: "2.0") do
          xml.head { xml.title "Starter feeds" }
          xml.body do
            wanted.group_by(&:folder).each do |folder, group|
              if folder.blank?
                group.each { |entry| outline(xml, entry) }
              else
                xml.outline(text: folder, title: folder) { group.each { |entry| outline(xml, entry) } }
              end
            end
          end
        end
      end
      builder.to_xml
    end

    def outline(xml, entry)
      xml.outline(type: "rss", text: entry.title, title: entry.title, xmlUrl: entry.url)
    end

    def document
      @document ||= File.exist?(PATH) ? PATH.read : ""
    end

    # A self-hoster who edits the file shouldn't have to restart to see it,
    # and the tests need it too.
    def reload!
      @entries = nil
      @document = nil
      self
    end
  end
end
