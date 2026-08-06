class CreateNotificationChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_channels do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.json :config, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :notification_channels, %i[ user_id kind ]
  end
end
