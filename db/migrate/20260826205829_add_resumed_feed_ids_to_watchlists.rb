class AddResumedFeedIdsToWatchlists < ActiveRecord::Migration[8.1]
  def change
    # Feeds the user told the flood guard to keep watching anyway
    # (D-story-matching §6): a resume is a decision, and the guard does not
    # get to overrule one — until the words change, which is a new question.
    add_column :watchlists, :resumed_feed_ids, :json, default: [], null: false
  end
end
