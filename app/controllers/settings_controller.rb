class SettingsController < ApplicationController
  def show
    @sections = Current.user.ordered_sections
    @agent_levels = Current.user.user_sections.pluck(:section_id, :agent_level).to_h
    @household_members = household_members
    @section_grants = Current.user.granted_access_grants.where(subject_type: "Section")
      .includes(:grantee, :subject)
    @linked_accounts = Current.user.linked_accounts.index_by(&:provider)
  end

  def update
    enabled_ids = params.fetch(:enabled_section_ids, []).map(&:to_i)
    ordered_ids = params.fetch(:section_order, []).map(&:to_i)
    agent_levels = params.fetch(:agent_levels, {})

    Section.top_level.each do |section|
      preference = Current.user.user_sections.find_or_initialize_by(section: section)
      preference.enabled = enabled_ids.include?(section.id)
      position = ordered_ids.index(section.id)
      preference.position = position + 1 if position
      level = agent_levels[section.id.to_s]
      preference.agent_level = level if UserSection::AGENT_LEVELS.include?(level)
      preference.save!
    end

    redirect_to settings_path, notice: "Sections updated."
  end

  private
    def household_members
      Current.user.household.users.where.not(id: Current.user.id).order(:name)
    end
end
