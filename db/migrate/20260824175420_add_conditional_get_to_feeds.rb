class AddConditionalGetToFeeds < ActiveRecord::Migration[8.1]
  def change
    change_table :feeds, bulk: true do |t|
      # Conditional GET (D-feed-reader): what the publisher said last time,
      # echoed back so an unchanged feed costs them a 304 and us nothing.
      # `last_modified` is the raw header rather than a timestamp — it goes
      # straight back out in If-Modified-Since, and reformatting a date is
      # how you turn a working cache into a broken one.
      t.string :etag
      t.string :last_modified
      # Denormalized from the items so the refresh sweep can ask "does
      # anybody still read this feed?" in SQL instead of one query per feed.
      t.datetime :last_read_at
    end
  end
end
