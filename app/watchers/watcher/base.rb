module Watcher
  # Superclass for watchers: subclasses implement `scan` and emit through
  # `suggest`, which enforces the fingerprint contract — an already-pending,
  # dismissed, or snoozed suggestion for the same subject is never
  # re-emitted. An accepted one may recur: the condition can genuinely
  # happen again.
  class Base
    class_attribute :section_slugs, instance_accessor: false, default: []

    def self.slug = name.demodulize.underscore

    def initialize(user)
      @user = user
    end

    def scan
      raise NotImplementedError
    end

    private
      attr_reader :user

      def suggest(fingerprint:, title:, body: nil, kind: :nudge, sections: [], action: {})
        return if user.suggestions.where(fingerprint: fingerprint).where.not(status: :accepted).exists?

        suggestion = user.suggestions.create!(
          watcher_slug: self.class.slug, fingerprint: fingerprint,
          title: title, body: body, kind: kind, action: action
        )
        suggestion.sections = sections
        suggestion
      end
  end
end
