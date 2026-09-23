# The FTUE (Q5, M4.1): four skippable steps — sections (and vault pages), agent voice,
# model (admins), bring-your-life-in. Reaching the last step marks the
# user onboarded, so its import links work like any other page; the whole
# flow stays revisitable via Settings.
class OnboardingController < ApplicationController
  skip_before_action :require_onboarding

  LAST_STEP = 4

  def show
    @step = step_param
    @step = LAST_STEP if @step == 3 && !Current.user.admin?

    # The last step offers a pet only when this user can't already see one:
    # the household's second member has no business being asked to add the dog
    # a second time (D-pet-primitive).
    @offer_pet = @step == LAST_STEP && !Pet.visible_to(Current.user).exists?

    Current.user.update!(onboarded_at: Time.current) if @step == LAST_STEP && Current.user.onboarded_at.nil?
  end

  def update
    case step_param
    when 1 then save_sections
    when 2 then save_agent_voice
    end

    redirect_to onboarding_path(step: step_param + 1)
  end

  private
    def step_param
      params.fetch(:step, 1).to_i.clamp(1, LAST_STEP)
    end

    def save_sections
      enabled_ids = params.fetch(:enabled_section_ids, []).map(&:to_i)
      Section.top_level.each do |section|
        preference = Current.user.user_sections.find_or_initialize_by(section: section)
        preference.enabled = enabled_ids.include?(section.id)
        preference.save!
      end

      # Only when the form sent the vault question at all — a stale step-1
      # form without it must not switch every vault page off.
      if params.key?(:enabled_vault_slugs)
        Current.user.update!(enabled_vault_slugs: Array(params[:enabled_vault_slugs]).compact_blank)
      end
    end

    def save_agent_voice
      level = params[:agent_voice] == "off" ? "off" : UserSection::DEFAULT_AGENT_LEVEL
      Section.top_level.each do |section|
        preference = Current.user.user_sections.find_or_initialize_by(section: section)
        preference.agent_level = level
        preference.save!
      end
    end
end
