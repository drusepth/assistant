class AddDigestToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :digest, :text
    add_column :users, :digest_generated_at, :datetime
  end
end
