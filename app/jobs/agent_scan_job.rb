# Runs watchers for one user, honoring the per-section dials (D20, M3.2):
# Off = never; Quiet = the weekly scan; Active = daily too. The loudest
# dial among a watcher's sections wins; a watcher with no sections (e.g.
# goal stall) runs at the Quiet default. Output stays in-app either way.
class AgentScanJob < ApplicationJob
  queue_as :default

  # Fan-out entry points for the recurring schedules (config/recurring.yml).
  def self.scan_all(cadence: :weekly)
    User.find_each { |user| perform_later(user, cadence: cadence.to_s) }
  end

  def perform(user, cadence: "weekly")
    noteworthy = []

    Watcher.all.each do |watcher|
      level = dial_for(user, watcher)
      next if level == "off"
      next if cadence == "daily" && level != "active"

      scan = watcher.new(user)
      scan.scan
      # Only Active sections may reach beyond the app (D22) — Quiet means
      # in-app, that's the dial's meaning.
      noteworthy.concat(scan.proposals) if level == "active"
    end

    NotifyJob.perform_later(user, noteworthy.map(&:title)) if noteworthy.any?

    generate_digest(user) if cadence == "weekly"
  end

  private
    # LLM phrasing rides the weekly scan, after the deterministic work, and
    # fails silently — the Dashboard's local summary never depends on it.
    def generate_digest(user)
      profile = user.household.model_profile
      return unless profile&.configured?

      Users::WeeklyDigest.new(user: user, profile: profile).call
    rescue Llm::Error => e
      # Still silent for the user — but not for whoever runs the box (D23).
      # No retry: the digest rides the weekly scan, and re-running the job
      # would re-run every watcher to re-attempt one phrasing call.
      AppError.record(e, source: self.class.name, user: user, context: { digest: true })
      nil
    end

    def dial_for(user, watcher)
      sections = Section.where(slug: watcher.section_slugs)
      return UserSection::DEFAULT_AGENT_LEVEL if sections.empty?

      levels = sections.map { |section| user.agent_level_for(section.parent || section) }
      UserSection::AGENT_LEVELS.reverse.find { |level| levels.include?(level) }
    end
end
