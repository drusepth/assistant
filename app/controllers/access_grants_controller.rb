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
    # Look the class up from a fixed allowlist — never reflect on params.
    def find_subject
      subject_classes = [ Event, Task, Document, Person, Goal, Note, Photo, Section ]
      klass = subject_classes.find { |candidate| candidate.name == params[:subject_type] }
      raise ActiveRecord::RecordNotFound if klass.nil?

      klass.find(params[:subject_id])
    end
end
