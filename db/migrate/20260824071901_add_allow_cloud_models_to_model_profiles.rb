class AddAllowCloudModelsToModelProfiles < ActiveRecord::Migration[8.1]
  def change
    # Defaults on, because turning it off with no local model configured
    # would leave a household with no AI at all. The recommendation lives in
    # the copy beside it, not in the default (D-local-first-models).
    add_column :model_profiles, :allow_cloud_models, :boolean, default: true, null: false
  end
end
