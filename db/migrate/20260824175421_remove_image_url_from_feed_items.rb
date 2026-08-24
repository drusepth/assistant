class RemoveImageUrlFromFeedItems < ActiveRecord::Migration[8.1]
  # The river is text (D-feed-reader): one line per item, no thumbnails. A
  # column nothing renders is a column that rots — the parser still reads
  # the entry's image (and refuses anything that isn't http(s)), so the day
  # an expanded item view lands it comes back with the view that shows it.
  def change
    remove_column :feed_items, :image_url, :string
  end
end
