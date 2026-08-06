class ModelProfilesController < ApplicationController
  before_action :require_admin

  def update
    profile = Current.user.household.model_profile || Current.user.household.build_model_profile
    attributes = params.expect(model_profile: [ :provider, :base_url, :model, :api_key ])
    attributes.delete(:api_key) if attributes[:api_key].blank? # blank = keep the stored key

    if profile.update(attributes)
      redirect_to settings_path, notice: "AI model settings saved."
    else
      redirect_to settings_path, alert: profile.errors.full_messages.to_sentence
    end
  end
end
