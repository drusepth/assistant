# The agent's signal layer (D20): watchers are deterministic scans — SQL
# over the user's own data, no model calls — that emit Suggestions. The LLM
# is optional garnish reserved for later milestones (phrasing, ranking, the
# digest); the *decision* that something deserves attention is always plain
# code. Like tools, watchers are first-party only and this explicit slug
# list is the whole registry.
#
# Three sanctioned exceptions to SQL-only, each on the same terms — one
# call, over a handful of rows rather than a firehose, for a judgment SQL
# genuinely cannot make. job_scout (D-career-web) ranks fresh postings from
# the user's configured feeds; subject_scout (docs/EDUCATION_PLAN.md §7)
# covers the lenses its deterministic affinity map doesn't know;
# hobby_from_feeds (D-hobby-feeds) reads the feeds nothing has filed and
# asks whether they share a subject worth naming. All three leave the
# write-surface discipline untouched: suggestions only, propose-don't-dispose.
module Watcher
  SLUGS = %w[
    checkup_cadence stay_in_touch birthday_radar renewal_radar goal_stall neglected_hobby
    hobby_from_feeds
    reviews_due subject_scout subject_stall rusty_radar pace_check
    same_day_sync stale_task on_this_day
    stub_anomaly raise_cadence interview_ahead application_follow_up real_terms_drift job_scout
    email_deadline email_reply_wanted email_no_reply email_unanswered
    budget_pace new_recurring_charge price_hike month_close email_receipt
    pet_care_cadence pet_food_reorder
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
