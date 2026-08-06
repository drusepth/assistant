class CreateModelProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :model_profiles do |t|
      t.references :household, null: false, foreign_key: true, index: { unique: true }
      t.string :base_url, null: false, default: "https://api.openai.com/v1"
      t.string :model, null: false, default: "gpt-4o-mini"
      t.string :api_key

      t.timestamps
    end
  end
end
