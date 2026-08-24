module Sections
  module Panels
    # The Hobbies lead panel (D25/docs/HOBBIES.md): lens cards with
    # engagement signal, or the what-do-you-do-for-fun capture before any
    # lens exists — plus the reader's own doorway (D-feed-reader), since a
    # hobby's feeds are the one thing on this page that changes daily.
    class Hobbies < Panel
      READER_PREVIEW = 3

      def feeds
        @feeds ||= viewer.feeds.includes(:sections).order(:created_at)
      end

      def river
        @river ||= Feeds::River.new(viewer, filter: "unread", sort: "interesting")
      end

      def unread_count = @unread_count ||= river.unread_count

      # The three the ranking would put at the top of the river right now —
      # a taste of the reader rather than a second reader on this page.
      def top_items = @top_items ||= river.page(per_page: READER_PREVIEW).items
    end
  end
end
