# The agent's signal layer (D20): watchers are deterministic scans — SQL
# over the user's own data, no model calls — that emit Suggestions. The LLM
# is optional garnish reserved for later milestones (phrasing, ranking, the
# digest); the *decision* that something deserves attention is always plain
# code. Like tools, watchers are first-party only and this explicit slug
# list is the whole registry.
#
# One sanctioned exception to SQL-only (D-career-web): job_scout fetches the user's
# configured feeds and ranks postings with one model call. The write-surface
# discipline is untouched — suggestions only, propose-don't-dispose.
module Watcher
  SLUGS = %w[
    checkup_cadence stay_in_touch birthday_radar renewal_radar goal_stall neglected_hobby
    same_day_sync stale_task on_this_day
    stub_anomaly raise_cadence interview_ahead application_follow_up real_terms_drift job_scout
    email_deadline email_reply_wanted email_no_reply email_unanswered
    budget_pace new_recurring_charge price_hike month_close email_receipt
  ].freeze

  module_function

  def all = SLUGS.map { |slug| find(slug) }

  def find(slug)
    const_get(slug.to_s.camelize) if SLUGS.include?(slug.to_s)
  end

  def find!(slug)
    find(slug) || raise(ActiveRecord::RecordNotFound, "no watcher named #{slug.inspect}")
  end
end
