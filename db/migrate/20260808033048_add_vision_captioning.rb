class AddVisionCaptioning < ActiveRecord::Migration[8.1]
  def change
    # We can't probe whether an OpenAI-compatible endpoint accepts images —
    # the household admin declares it (D-photos-primitive/W5).
    add_column :model_profiles, :vision, :boolean, default: false, null: false

    add_column :photos, :caption_status, :string
    add_column :photos, :caption_error, :string
    add_column :photos, :suggested_sections, :json, default: []
  end
end
