class SettingsController < ApplicationController
  def show
    @sections = Current.user.ordered_sections
    @agent_levels = Current.user.user_sections.pluck(:section_id, :agent_level).to_h
    @household_members = household_members
    @section_grants = Current.user.granted_access_grants.where(subject_type: "Section")
      .includes(:grantee, :subject)
    # Grouped, not indexed: a provider may be linked more than once
    # (multi: true — one row per mailbox).
    @linked_accounts = Current.user.linked_accounts.order(:created_at).group_by(&:provider)
    # The transparency line under the prepared-work switch: the agent is the
    # one thing in the app that spends model calls without being asked, so
    # what it spent is shown where the switch to stop it is. Derived from
    # the runs themselves — no bookkeeping of its own.
    @drafts_prepared = Current.user.tool_runs.origin_agent.where(created_at: 7.days.ago..).count
  end

  def update
    # The celebration switch posts here too, and posts nothing else — so it
    # returns before the section loop, which reads "no sections checked" as
    # "turn every section off".
    if params.key?(:celebrations)
      Current.user.update!(celebrations: params[:celebrations] == "1")
      return redirect_to settings_path,
        notice: Current.user.celebrations? ? "Celebrations on. 🎉" : "Celebrations off."
    end

    # The /about switch (D-about-pages). Admin-only and household-wide —
    # it is the instance's front door, not one member's preference — and
    # another early return, for the same reason as celebrations.
    if params.key?(:public_pages)
      return redirect_to settings_path, alert: "Only household admins can do that." unless Current.user.admin?

      Current.user.household.update!(public_pages_enabled: params[:public_pages] == "1")
      return redirect_to settings_path,
        notice: Current.user.household.public_pages_enabled? ? "Public pages are on." : "Public pages are off."
    end

    # The prepared-work switch (D-agent-prepared-work) — same early-return
    # shape as celebrations, for the same reason.
    if params.key?(:prepare_work)
      Current.user.update!(prepare_work: params[:prepare_work] == "1")
      return redirect_to settings_path, notice: Current.user.prepare_work? ?
        "Your assistant will draft ahead in Active sections." :
        "Your assistant will stop drafting ahead."
    end

    # The work-profile card (D-work-profile) posts here too, and posts
    # nothing else — same early return as celebrations for the same reason.
    if params.key?(:work)
      Current.user.update!(params.fetch(:work, {}).permit(:job_title, :employer))
      return redirect_to settings_path, notice: "Work profile saved."
    end

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
