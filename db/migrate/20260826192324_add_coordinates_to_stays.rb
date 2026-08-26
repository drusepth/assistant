# A stay's coordinates come from matching its typed location against the
# local gazetteer (D-stay-pins) — never from photo EXIF, never from the
# network — so the itinerary can draw on the self-drawn basemap.
class AddCoordinatesToStays < ActiveRecord::Migration[8.1]
  def change
    add_column :stays, :latitude, :decimal, precision: 10, scale: 6
    add_column :stays, :longitude, :decimal, precision: 10, scale: 6
  end
end
