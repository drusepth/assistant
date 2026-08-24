module Diary
  # Leaving (DIARY_PLAN §6). Markdown files with front matter — the format
  # every other journal app reads, and the one a person can still open in
  # thirty years with no software at all — plus a manifest.
  #
  # In-request and password-confirmed, for the same reason as the passwords
  # export: key material never rides the job queue, so the archive job
  # cannot produce this and the button has to.
  class Export
    FORMAT_VERSION = 1

    def initialize(session)
      @session = session
      @user = session.user
    end

    def zip
      opened = @session.open_all(@user.diary_entries.order(:entry_date, :id))
      readable = opened.reject(&:lost?)

      Zip::OutputStream.write_buffer do |archive|
        archive.put_next_entry("manifest.json")
        archive.write(JSON.pretty_generate(manifest(opened, readable)))

        names = Hash.new(0)
        readable.each do |entry|
          name = entry_name(entry, names)
          archive.put_next_entry("entries/#{name}")
          archive.write(markdown(entry))
        end
      end.tap(&:rewind)
    end

    def filename = "diary-#{Date.current.iso8601}.zip"

    private
      def manifest(opened, readable)
        {
          format: "assistant-diary", version: FORMAT_VERSION,
          exported_at: Time.current.iso8601,
          author: @user.name,
          entries: readable.size,
          unreadable: opened.size - readable.size,
          note: "One Markdown file per entry under entries/, with YAML front matter. " \
                "This file is the only copy that isn't encrypted — keep it somewhere you'd keep a paper diary."
        }.compact
      end

      # Several entries can share a day, so the name gets a suffix rather
      # than one silently overwriting another inside the zip.
      def entry_name(opened, names)
        date = opened.entry.entry_date.iso8601
        names[date] += 1
        suffix = names[date] > 1 ? "-#{names[date]}" : ""
        "#{date}#{suffix}.md"
      end

      def markdown(opened)
        front = { "date" => opened.entry.entry_date.iso8601 }
        front["title"] = quote(opened.title) if opened.title
        front["mood"] = quote(opened.mood) if opened.mood

        <<~MARKDOWN
          ---
          #{front.map { |key, value| "#{key}: #{value}" }.join("\n")}
          ---

          #{opened.body}
        MARKDOWN
      end

      # Front matter is read back by our own importer and by other tools;
      # quoting keeps a colon in a title from turning into a second key.
      def quote(value) = %("#{value.to_s.gsub('"', '\"')}")
  end
end
