# The Agent mode's signal source (D20): a watcher is a deterministic scan
# over a user's own data that emits candidate suggestions. The signal comes
# from SQL, not model calls — cheap, private, and identical with every model
# (including none). Watchers are code with an explicit registry, exactly
# like tools (D11/D19): first-party only.
module Watcher
  SLUGS = %w[ neglected_hobby ].freeze

  module_function

  def all = SLUGS.map { |slug| find!(slug) }

  def find!(slug)
    raise ActiveRecord::RecordNotFound, "no watcher named #{slug.inspect}" unless SLUGS.include?(slug.to_s)

    const_get(slug.to_s.camelize)
  end
end
