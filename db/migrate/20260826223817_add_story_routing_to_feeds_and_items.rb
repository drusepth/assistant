class AddStoryRoutingToFeedsAndItems < ActiveRecord::Migration[8.1]
  def change
    # Does this feed publish about one subject, or many? The model answers
    # it once, when it files the feed (D-story-matching): a focused feed's
    # stories inherit its hobbies and are never read individually, and a
    # broad one's are the only stories that cost anything.
    add_column :feeds, :broad, :boolean

    # Has the router looked at this story yet? Null means not yet; a stamp
    # means considered, whether or not anything was routed.
    add_column :feed_items, :routed_at, :datetime
    add_index :feed_items, [ :feed_id, :routed_at ]
  end
end
