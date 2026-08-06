class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.references :household, null: false, foreign_key: true
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.datetime :accepted_at

      t.timestamps
    end
  end
end
