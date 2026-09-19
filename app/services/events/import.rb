# Imports a calendar export into the user's Events. Modular by design, same
# shape as People::Import: each format is a parser class in Events::Import::
# that answers `handles?` and emits normalized ParsedEvents; adding a format
# means adding a parser to FORMATS. Everything funnels through the same
# Event-building code here.
class Events::Import
  # What every parser emits, regardless of source format. starts_at/ends_at
  # are times (all-day events carry midnight in the app zone, ends_at nil for
  # a single day); anything the Event columns can't hold is folded into
  # description by the parser so nothing is dropped.
  #
  # `uid`, `url`, `geo` ([lat, lng]) and `recurring` are what the event radar
  # keeps that the calendar import doesn't need (D-listing-feeds): the import
  # folds the link into the description and dedupes by title + time, exactly
  # as before, and never reads these four.
  ParsedEvent = Struct.new(
    :title, :description, :location, :starts_at, :ends_at, :all_day,
    :uid, :url, :geo, :recurring,
    keyword_init: true
  )

  Result = Struct.new(:imported, :skipped, :error, keyword_init: true)

  # Ordered: specific formats first, the header-sniffing generic CSV last.
  FORMATS = [
    Events::Import::Ics,
    Events::Import::OutlookCsv,
    Events::Import::GenericCsv
  ].freeze

  # Takes either an uploaded file or raw content + filename — the latter is
  # how live syncs (Events::CaldavSync) reuse this exact pipeline, so a
  # sync and an upload can never parse or dedupe differently.
  def initialize(user:, file: nil, content: nil, filename: nil)
    @user = user
    if file
      @filename = file.respond_to?(:original_filename) ? file.original_filename : File.basename(file.to_path)
      @content = normalize_encoding(file.read)
    else
      @filename = filename.to_s
      @content = normalize_encoding(content.to_s.dup)
    end
  end

  def call
    parser = FORMATS.find { |format| format.handles?(@filename, @content) }
    unless parser
      return Result.new(imported: 0, skipped: 0,
        error: "That file doesn't look like a calendar export. Use an iCalendar (.ics) or CSV export from your calendar app.")
    end

    events = parser.new(@content).events.select { |e| e.title.present? && e.starts_at.present? }
    if events.empty?
      return Result.new(imported: 0, skipped: 0, error: "No events found in that file.")
    end

    import(events)
  end

  private
    # Deliberately no section tagging and no auto-sort: a calendar can carry
    # hundreds of events and per-item categorize jobs would hammer the model
    # (same call as People::Import made). The Calendar view shows every event
    # regardless of section, so untagged imports are fully usable.
    def import(events)
      existing = @user.events.pluck(:title, :starts_at).to_set { |title, starts_at| [ title.downcase.squish, starts_at.to_i ] }
      imported = 0
      skipped = 0

      Event.transaction do
        events.each do |event|
          key = [ event.title.downcase.squish, event.starts_at.to_i ]
          if existing.include?(key)
            skipped += 1
            next
          end
          existing << key

          @user.events.create!(
            title: event.title.squish,
            description: event.description,
            location: event.location,
            starts_at: event.starts_at,
            ends_at: event.ends_at,
            all_day: !!event.all_day
          )
          imported += 1
        end
      end

      Result.new(imported: imported, skipped: skipped)
    end

    def normalize_encoding(raw)
      raw.force_encoding(Encoding::UTF_8)
      raw = raw.valid_encoding? ? raw : raw.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
      raw.delete_prefix("\u{FEFF}").scrub
    end
end
