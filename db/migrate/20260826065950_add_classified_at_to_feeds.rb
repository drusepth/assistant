class AddClassifiedAtToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_column :feeds, :classified_at, :datetime
  end
end
