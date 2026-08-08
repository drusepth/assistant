# Per-user digest scheduling (EMAIL_PLAN.md §7): a user's delivery time
# is their own, on the household clock — so one fixed cron entry can't
# work. The dispatcher runs every 15 minutes and fires each user's digest
# once their chosen local hour arrives, at most once per local day.
class Email::DigestJob < ApplicationJob
  queue_as :default

  def self.dispatch_due
    User.joins(:linked_accounts).where(linked_accounts: { provider: "email" }).distinct.find_each do |user|
      now = Time.current.in_time_zone(user.household.tz.name)
      next if now.hour < user.mail_digest_hour
      next if user.mail_digest_generated_on == now.to_date

      perform_later(user)
    end
  end

  def perform(user)
    return unless user.linked_accounts.where(provider: "email").any?

    Email::Digest.new(user).call
  end
end
