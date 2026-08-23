class CreateShareLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :share_links do |t|
      t.references :user, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      # ~140 bits of urlsafe token: the whole authorization for a public,
      # unauthenticated read path (D-share-link).
      t.string :token, null: false
      t.string :label
      t.datetime :expires_at
      t.integer :views_count, null: false, default: 0
      t.datetime :last_viewed_at

      t.timestamps
    end
    add_index :share_links, :token, unique: true
  end
end
