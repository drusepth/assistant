class AddProviderToModelProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :model_profiles, :provider, :string, null: false, default: "openai"
    change_column_null :model_profiles, :model, true

    # Profiles that were pointed at a non-OpenAI endpoint before providers
    # existed keep working as custom endpoints.
    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE model_profiles SET provider = 'custom'
          WHERE base_url <> 'https://api.openai.com/v1'
        SQL
      end
    end
  end
end
