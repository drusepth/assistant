# The agent's signal layer (D20): watchers are deterministic scans — SQL
# over the user's own data, no model calls — that emit Suggestions. The LLM
# is optional garnish reserved for later milestones (phrasing, ranking, the
# digest); the *decision* that something deserves attention is always plain
# code. Like tools, watchers are first-party only and this explicit slug
# list is the whole registry.
module Watcher
  SLUGS = %w[ checkup_cadence stay_in_touch renewal_radar goal_stall same_day_sync ].freeze

  module_function

  def all = SLUGS.map { |slug| find(slug) }

  def find(slug)
    const_get(slug.to_s.camelize) if SLUGS.include?(slug.to_s)
  end

  def find!(slug)
    find(slug) || raise(ActiveRecord::RecordNotFound, "no watcher named #{slug.inspect}")
  end
end
