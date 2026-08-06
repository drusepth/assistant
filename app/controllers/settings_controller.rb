class SettingsController < ApplicationController
  def show
    @sections = Current.user.ordered_sections
    @household_members = household_members
    @section_grants = Current.user.granted_access_grants.where(subject_type: "Section")
      .includes(:grantee, :subject)
    @pending_invitations = Current.user.household.invitations.pending.order(:created_at) if Current.user.admin?
  end

  def update
    enabled_ids = params.fetch(:enabled_section_ids, []).map(&:to_i)
    ordered_ids = params.fetch(:section_order, []).map(&:to_i)

    Section.top_level.each do |section|
      preference = Current.user.user_sections.find_or_initialize_by(section: section)
      preference.enabled = enabled_ids.include?(section.id)
      position = ordered_ids.index(section.id)
      preference.position = position + 1 if position
      preference.save!
    end

    redirect_to settings_path, notice: "Sections updated."
  end

  private
    def household_members
      Current.user.household.users.where.not(id: Current.user.id).order(:name)
    end
end
