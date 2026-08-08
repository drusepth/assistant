class AccessGrantsController < ApplicationController
  def create
    return share_with_household if params[:everyone].present?

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
    # The D30 convenience: "share with everyone" is ordinary per-member
    # grants created in bulk — no new mechanism, and a member who joins the
    # household later still sees nothing until shared with explicitly.
    def share_with_household
      subject = find_subject
      Current.user.household.users.where.not(id: Current.user.id).find_each do |member|
        Current.user.granted_access_grants.find_or_create_by(grantee: member, subject: subject)
      end
      redirect_back fallback_location: settings_path, notice: "Shared with everyone in the household."
    end

    # Look the class up from a fixed allowlist — never reflect on params.
    def find_subject
      subject_classes = [ Event, Task, Document, Person, Goal, Note, Photo, Album, Section ]
      klass = subject_classes.find { |candidate| candidate.name == params[:subject_type] }
      raise ActiveRecord::RecordNotFound if klass.nil?

      klass.find(params[:subject_id])
    end
end
