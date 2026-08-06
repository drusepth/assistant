# Where the agent may reach you off-app (D22). Three kinds, none assumed:
# webhook (ntfy/Home Assistant/Matrix — the self-hoster ecosystem), Web
# Push (per-instance VAPID, no third party), email (only useful when the
# instance has SMTP). Only Active-dial sections ever notify, batched per
# scan, counts and titles only — a lock screen is not private by default.
class NotificationChannel < ApplicationRecord
  belongs_to :user

  enum :kind, { webhook: "webhook", web_push: "web_push", email: "email" }

  validates :config, presence: true
  validate :config_shape

  scope :active, -> { where(enabled: true) }

  def label
    case kind
    when "webhook" then "Webhook — #{config["url"].to_s.truncate(60)}"
    when "web_push" then "Browser push — added #{created_at.strftime("%b %-d, %Y")}"
    when "email" then "Email — #{config["address"]}"
    end
  end

  private
    def config_shape
      case kind
      when "webhook"
        url = config["url"].to_s
        errors.add(:base, "Webhook needs an http(s) URL.") unless url.start_with?("http://", "https://")
      when "web_push"
        subscription = config["subscription"] || {}
        unless subscription["endpoint"].present? && subscription.dig("keys", "p256dh").present? && subscription.dig("keys", "auth").present?
          errors.add(:base, "That browser subscription looks incomplete — try enabling push again.")
        end
      when "email"
        errors.add(:base, "Email needs an address.") unless config["address"].to_s.include?("@")
      end
    end
end
