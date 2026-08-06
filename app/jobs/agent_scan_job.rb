# Runs every watcher for one user. M3.1 hardwires the Quiet dial for
# everyone: a weekly scan whose output appears in-app only (Dashboard +
# section Attend zones). Per-section Off/Quiet/Active dials arrive in M3.2
# on user_sections, and this job is where they'll be honored.
class AgentScanJob < ApplicationJob
  queue_as :default

  # Fan-out entry point for the recurring schedule (config/recurring.yml).
  def self.scan_all
    User.find_each { |user| perform_later(user) }
  end

  def perform(user)
    Watcher.all.each do |watcher|
      next unless watched_section_enabled?(user, watcher)

      watcher.new(user).scan
    end
  end

  private
    # A watcher on a disabled section stays silent — the section toggle is
    # the coarse dial until the real ones ship.
    def watched_section_enabled?(user, watcher)
      Section.where(slug: watcher.section_slugs).any? do |section|
        user.section_enabled?(section.parent || section)
      end
    end
end
