module Sections
  module Panels
    # One hobby's page (D-hobby-feeds). Reached through Panel's parent-lens
    # fallback rather than by name, because a lens is a row the user made and
    # no class can be named after its slug.
    #
    # This is the "filter to one hobby" half of the hub: the same river, the
    # same density, narrowed to the feeds filed under this lens — with the
    # everything-view one link away. Deeper than the hub card (a screenful,
    # not a taste) and shallower than /reader (no filter rows, no paging):
    # the page's other zones are what you came for, and the river is the part
    # that changed since yesterday.
    class HobbiesLens < Panel
      PREVIEW = 12

      def row = @row ||= ::Hobbies::Rivers.for(viewer, [ section ], preview: PREVIEW).sole

      def feeds = row.feeds
      def items = row.items
      def unread_count = row.unread_count
    end
  end
end
