class CreateTrips < ActiveRecord::Migration[8.1]
  # A saved trip (D-travel-facet) is a name, a date range and a box on the
  # map — nothing else. Membership is derived from those three: the photos
  # are the ones taken inside the box during the range, and the events are
  # the ones in the range. That keeps Q17 deferred (no polymorphic link
  # table) and means a trip stays correct as photos arrive.
  def change
    create_table :trips do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false

      # The bounding box of the trip's photos when it was saved.
      t.decimal :south, precision: 10, scale: 6, null: false
      t.decimal :west, precision: 10, scale: 6, null: false
      t.decimal :north, precision: 10, scale: 6, null: false
      t.decimal :east, precision: 10, scale: 6, null: false

      # What the gazetteer called it at save time, kept so a later change of
      # dataset never silently relabels someone's history.
      t.string :place_label
      t.integer :cover_photo_id

      t.timestamps
    end

    add_index :trips, [ :user_id, :starts_on ]
  end
end
