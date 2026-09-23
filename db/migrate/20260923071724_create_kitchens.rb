class CreateKitchens < ActiveRecord::Migration[8.1]
  def change
    # The household's shared kitchen (D-kitchen): one container whose lists,
    # fridge and meal plan are its rows, and a grant on which lets the
    # grantee cook.
    create_table :kitchens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false, default: "Home"
      # When the owner answered "share this kitchen with the household?" —
      # either way. The card stays on the hub until then.
      t.datetime :share_prompt_answered_at
      t.timestamps
    end

    # Which kitchen the Food hub opens on, for someone who can see more
    # than one (their own and a partner's, or the cabin).
    add_reference :users, :current_kitchen, foreign_key: { to_table: :kitchens, on_delete: :nullify }
  end
end
