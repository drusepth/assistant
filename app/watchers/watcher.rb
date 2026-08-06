# The agent's sensing layer (D20): a watcher is a class with a slug,
# sections, and scan — deterministic SQL over the user's own data, no model
# calls. The signal comes from queries; the LLM is optional garnish that
# arrives in M3.3. Like tools, watchers are code and this list is the whole
# registry.
module Watcher
  SLUGS = %w[ checkup_cadence ].freeze

  module_function

  def all = SLUGS.map { |slug| find!(slug) }

  def find(slug)
    const_get(slug.to_s.camelize) if SLUGS.include?(slug.to_s)
  end

  def find!(slug)
    find(slug) || raise(ActiveRecord::RecordNotFound, "no watcher named #{slug.inspect}")
  end
end
