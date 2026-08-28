# Runs watchers for one user, honoring the per-section dials (D20, M3.2):
# Off = never; Quiet = the weekly scan; Active = daily too. The loudest
# dial among a watcher's sections wins; a watcher with no sections (e.g.
# goal stall) runs at the Quiet default. Output stays in-app either way.
class AgentScanJob < ApplicationJob
  queue_as :default

  # Preparations attempted per user per scan (D-agent-prepared-work).
  # Counted as attempts, not successes: this is the first thing the agent
  # spends model tokens on without a click, so the cap has to bound the
  # spending rather than the yield. Whatever doesn't fit stays an ordinary
  # prefilled redirect, which is no worse than last week.
  PREPARE_BUDGET = 3

  # Fan-out entry points for the recurring schedules (config/recurring.yml).
  def self.scan_all(cadence: :weekly)
    User.find_each { |user| perform_later(user, cadence: cadence.to_s) }
  end

  def perform(user, cadence: "weekly")
    noteworthy = []

    retire_expired(user)

    Watcher.all.each do |watcher|
      level = dial_for(user, watcher)
      next if level == "off"
      next if cadence == "daily" && level != "active"

      # Retiring first, before the scan (D-suggestion-lifecycle): a watcher
      # that caps its live suggestions (stale task's three slots) should
      # spend those slots on what still matters, so freeing the handled ones
      # has to happen before the scan counts them.
      retire_resolved(user, watcher)

      begin
        scan = watcher.new(user)
        scan.scan
        # Only Active sections may reach beyond the app (D22) — Quiet means
        # in-app, that's the dial's meaning.
        noteworthy.concat(scan.proposals) if level == "active"
      rescue StandardError => e
        # One broken watcher must not silence the rest of the scan — record
        # it for /admin (D23) and keep going.
        record_failure(e, user: user, context: { watcher: watcher.name })
      end
    end

    if noteworthy.any?
      NotifyJob.perform_later(user, noteworthy.map(&:title), suggestion_ids: noteworthy.map(&:id))
    end
    prepare_work(user, noteworthy)

    generate_digest(user) if cadence == "weekly"
  end

  private
    # Drafts the work behind the suggestions this scan just made
    # (D-agent-prepared-work). The candidate set is `noteworthy` — the
    # proposals from Active-dial watchers — which is the same set the
    # notification speaks about, and rightly so: Active means both "tell me"
    # and "have it ready". Quiet keeps exactly today's behavior.
    #
    # Newly-proposed only, by construction: a suggestion re-surfacing from a
    # snooze was never in this list, so nothing is ever prepared twice.
    def prepare_work(user, noteworthy)
      return if noteworthy.empty?
      return unless user.prepare_work?
      # With no model configured the feature silently does not exist —
      # nothing errors and nothing apologizes.
      return unless user.household.model_profile&.configured?

      noteworthy.select(&:preparable_tool).first(PREPARE_BUDGET).each do |suggestion|
        AgentPrepareJob.perform_later(suggestion)
      end
    rescue StandardError => e
      record_failure(e, user: user, context: { prepare: true })
    end

    # The dateless half of the lifecycle (D-suggestion-lifecycle): anything
    # whose subject moment has passed retires without consulting a watcher.
    # Deliberately outside the dial loop — an expired nudge is stale in a
    # section the user has since turned Off too, and cleaning it up is not
    # the agent speaking.
    def retire_expired(user)
      user.suggestions.actionable.find_each { |suggestion| suggestion.resolve! if suggestion.expired? }
    rescue StandardError => e
      record_failure(e, user: user, context: { retire: "expired" })
    end

    # The watcher-answered half: each watcher is asked whether its own live
    # suggestions have been overtaken by events. Isolated exactly like the
    # scan is — a watcher whose `resolved?` raises must not cost the user
    # their scan, and must not stop the other watchers retiring.
    def retire_resolved(user, watcher)
      return unless watcher.respond_to?(:retires?) && watcher.retires?

      live = user.suggestions.actionable.where(watcher_slug: watcher.slug)
      return if live.none?

      check = watcher.new(user)
      live.find_each { |suggestion| suggestion.resolve! if check.resolved?(suggestion) }
    rescue StandardError => e
      record_failure(e, user: user, context: { watcher: watcher.name, retire: true })
    end

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
