module Diary
  # Walks a staged import (DiaryImport) a batch at a time. The rows were
  # parsed and deduplicated once, at staging, so this is deliberately a dumb
  # loop: take a slice, seal it, move the cursor.
  #
  # Because the cursor lives in the database rather than in the request, a
  # closed tab pauses an import instead of losing one — and a resumed import
  # can't double-write, since the cursor only ever moves forward.
  class ImportRun
    Progress = Struct.new(:done, :cursor, :total, :imported, :skipped, :percent, :error)

    def initialize(session, import)
      @session = session
      @import = import
      @user = session.user
    end

    def step!(size: DiaryImport::BATCH)
      return progress(done: true) if @import.finished?

      rows = @import.next_batch(@session.diary_key, size: size)
      # An unopenable staging row means the diary key changed under us — a
      # password reset in another tab, mid-import. Nothing can be recovered
      # from it, so say so rather than looping forever on an empty batch.
      return failed("Your vault changed while this import was running — start it again.") if rows.blank?

      written = write(rows)
      @import.update!(cursor: @import.cursor + rows.size, imported: @import.imported + written)

      finish if @import.finished?
      progress(done: @import.finished?)
    end

    private
      def write(rows)
        rows.count do |row|
          date = parse_date(row["date"])
          next false if date.nil?

          entry = @user.diary_entries.new(entry_date: date)
          @session.write!(entry, { "title" => row["title"], "body" => row["body"] })
          true
        end
      end

      def parse_date(value)
        Date.parse(value.to_s)
      rescue Date::Error
        nil
      end

      # The staged plaintext is the point of this row; once it's written
      # there is no reason to keep a sealed copy of the same words around.
      def finish
        @totals = { imported: @import.imported, skipped: @import.skipped }
        @import.destroy!
      end

      def progress(done:)
        totals = @totals || { imported: @import.imported, skipped: @import.skipped }
        Progress.new(done, @import.cursor, @import.total, totals[:imported], totals[:skipped],
          done ? 100 : @import.percent, nil)
      end

      def failed(message)
        @import.destroy!
        Progress.new(true, 0, 0, 0, 0, 100, message)
      end
  end
end
