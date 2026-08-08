# Tuning the care radar (docs/HEALTH.md §3): mute a kind, change its
# rhythm, add your own. Settings are the current user's — whose care it
# is — and a missing row means registry defaults.
class CareSettingsController < ApplicationController
  def show
    @radar = Health::CareRadar.new(Current.user)
    @settings = Current.user.care_settings.index_by(&:kind_key)
    @custom_settings = Current.user.care_settings.custom.order(:created_at)
  end

  def update
    allowed = Health::CareRadar::KINDS.map(&:key) + Current.user.care_settings.custom.pluck(:kind_key)
    params.fetch(:kinds, {}).slice(*allowed).each do |kind_key, attrs|
      attrs = attrs.permit(:enabled, :interval_months)
      setting = Current.user.care_settings.find_or_initialize_by(kind_key: kind_key)
      setting.enabled = attrs[:enabled] == "1"
      setting.interval_months = attrs[:interval_months].presence
      setting.save!
    end
    add_custom_kind if params.dig(:new_kind, :label).present?

    redirect_to care_settings_path, notice: flash[:alert] ? nil : "Care radar updated."
  end

  def destroy
    Current.user.care_settings.custom.find_by!(kind_key: params[:kind_key]).destroy!
    redirect_to care_settings_path, notice: "Removed — its events stay on the calendar."
  end

  private
    def add_custom_kind
      label = params[:new_kind][:label].to_s.squish
      key = label.parameterize(separator: "_")
      if key.blank? || Health::CareRadar::KINDS.any? { |kind| kind.key == key }
        flash[:alert] = "The radar already tracks #{label.presence || "that"}."
        return
      end

      setting = Current.user.care_settings.create(
        kind_key: key, label: label,
        interval_months: params[:new_kind][:interval_months].presence
      )
      flash[:alert] = setting.errors.full_messages.to_sentence if setting.invalid?
    end
end
