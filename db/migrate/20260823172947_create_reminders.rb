class CreateReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :reminders do |t|
      t.references :user, null: false, foreign_key: true
      # Optional on purpose: "remind me to call the pharmacy at 4pm" hangs
      # on nothing, and that is the case the feature exists for.
      t.string :subject_type
      t.integer :subject_id
      t.text :body, null: false
      # Always absolute, even for a reminder set as "an hour before" — the
      # dispatcher stays one indexed query, and the lead time is re-applied
      # whenever the item it counts back from moves.
      t.datetime :deliver_at, null: false
      t.integer :lead_minutes
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :reminders, %i[ subject_type subject_id ]
    # The dispatcher's whole query: what is pending and due.
    add_index :reminders, %i[ delivered_at deliver_at ]
  end
end
