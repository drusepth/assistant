class AccessGrantsController < ApplicationController
  def create
    grant = Current.user.granted_access_grants.new(
      grantee_id: params[:grantee_id], subject: find_subject
    )

    if grant.save
      redirect_back fallback_location: settings_path, notice: "Shared with #{grant.grantee.name}."
    else
      redirect_back fallback_location: settings_path, alert: grant.errors.full_messages.to_sentence
    end
  end

  def destroy
    grant = Current.user.granted_access_grants.find(params[:id])
    grant.destroy!
    redirect_back fallback_location: settings_path, notice: "Sharing revoked."
  end

  private
    def find_subject
      type = params[:subject_type]
      raise ActiveRecord::RecordNotFound unless AccessGrant::ITEM_TYPES.include?(type) || type == "Section"

      type.constantize.find(params[:subject_id])
    end
end
