module Sections
  module Panels
    # The Travel hub's lead panel (D-travel-facet, docs/TRAVEL.md).
    #
    # Travel starts as a lens with one thing in it: the map of everywhere
    # the household's cameras have been. That is deliberate — the section
    # earns its place on day one by showing something nobody had to type,
    # out of photos that were already in the library. Trips, packing,
    # documents and the rest come later; they'll be more panels here, not a
    # different page.
    #
    # The map is not filtered to Travel-tagged photos. Sections are lenses
    # over one pool, and the honest lens for "where have I been" is every
    # photo that knows where it was taken — not the subset somebody
    # remembered to tag.
    class Travel < Panel
      def map = @map ||= Photos::Map.new(viewer.photos)

      def unplaced_count = @unplaced_count ||= viewer.photos.where(latitude: nil).count

      def photos_count = @photos_count ||= viewer.photos.count
    end
  end
end
