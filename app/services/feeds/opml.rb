module Feeds
  # OPML in and out (D-feed-reader) — the format every reader since 2000 has
  # agreed on, which is the only reason a reading list can survive its
  # reader. An app whose whole argument is that you should own your things
  # has no business being the place a subscription list gets stuck: this is
  # the same reasoning as the export archive (D14/M4.2), in the format the
  # rest of the world can actually read.
  #
  # OPML's nested outlines are folders, and this app already has folders —
  # hobby lenses (D25). So a lens becomes a folder on the way out, and a
  # folder matches a lens by name on the way in. Import will *create* a
  # missing lens only when the user asks it to: silently adding thirty
  # sections to somebody's taxonomy because their old reader had thirty
  # folders is not an import, it's a mess.
  module Opml
    MAX_FEEDS = 500
    MAX_BYTES = 2.megabytes

    Result = Data.define(:added, :skipped, :lenses, :error) do
      def ok? = error.nil?
    end

    module_function

    def export(user)
      feeds = user.feeds.includes(:sections).order(:created_at).to_a
      by_lens = feeds.group_by { |feed| feed.sections.first }

      builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.opml(version: "2.0") do
          xml.head do
            xml.title "#{user.name}'s feeds"
            xml.dateCreated Time.current.rfc822
          end
          xml.body do
            # Untagged feeds sit at the top level, where every reader shows
            # them; the rest nest under their hobby.
            Array(by_lens[nil]).each { |feed| outline(xml, feed) }
            by_lens.except(nil).sort_by { |lens, _| lens.name.downcase }.each do |lens, lens_feeds|
              xml.outline(text: lens.name, title: lens.name) do
                lens_feeds.each { |feed| outline(xml, feed) }
              end
            end
          end
        end
      end
      builder.to_xml
    end

    def outline(xml, feed)
      attributes = {
        type: "rss", text: feed.display_title, title: feed.display_title, xmlUrl: feed.url
      }
      attributes[:htmlUrl] = feed.site_url if feed.site_url.present?
      xml.outline(attributes)
    end

    # Every `xmlUrl` in the document, with the folder it sat in. Malformed
    # entries are skipped rather than fatal — the same forgiveness the feed
    # parser extends, for the same reason: these files come from other
    # people's software.
    def entries(xml)
      document = Nokogiri::XML(xml.to_s) { |config| config.recover.nonet }
      return [] unless document.root

      document.css("outline[xmlUrl]").filter_map do |outline|
        url = outline["xmlUrl"].to_s.strip
        next unless url.match?(%r{\Ahttps?://\S+\z}i)

        folder = outline.ancestors("outline").first
        { url: url, label: outline["title"].presence || outline["text"].presence,
          folder: folder && (folder["title"].presence || folder["text"].presence) }
      end.uniq { |entry| entry[:url] }.first(MAX_FEEDS)
    rescue Nokogiri::XML::SyntaxError
      []
    end

    # Nothing here fetches: an import is a file the user handed us, and the
    # feeds it names are checked by the ordinary background refresh.
    def import(user, xml, create_lenses: false)
      return Result.new(added: 0, skipped: 0, lenses: [], error: "That file is too big to be an OPML export.") if
        xml.to_s.bytesize > MAX_BYTES

      found = entries(xml)
      return Result.new(added: 0, skipped: 0, lenses: [], error: "No feeds in that file — is it an OPML export?") if found.empty?

      added = 0
      skipped = 0
      lenses = []

      found.each do |entry|
        feed = user.feeds.new(url: entry[:url], label: entry[:label]&.truncate(200))
        lens = lens_for(entry[:folder], create: create_lenses)
        feed.sections = [ lens ] if lens

        if feed.save
          added += 1
          lenses |= [ lens.name ] if lens
          RefreshFeedJob.perform_later(feed)
        else
          skipped += 1
        end
      end

      Result.new(added: added, skipped: skipped, lenses: lenses, error: nil)
    end

    def lens_for(folder, create:)
      return nil if folder.blank?

      existing = Hobbies::Lens.named(folder)
      return existing if existing

      Hobbies::Lens.find_or_create!(folder) if create
    end
  end
end
