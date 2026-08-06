module Watcher
  # Superclass for watchers: scan(a user's own data) → propose suggestions.
  # propose is idempotent by fingerprint — one row per (user, watcher,
  # subject) ever, so a dismissed nudge stays dismissed (D20) and re-scans
  # never duplicate a pending one. Emitting under a fresh fingerprint (a new
  # year, a new subject) is how a watcher legitimately speaks again.
  class Base
    class_attribute :section_slugs, instance_accessor: false, default: []

    class << self
      def slug = name.demodulize.underscore

      def section_records = Section.where(slug: section_slugs)
    end

    def initialize(user)
      @user = user
    end

    def scan = raise(NotImplementedError)

    private
      attr_reader :user

      def propose(fingerprint:, title:, body: nil, kind: :nudge, action: {}, sections: self.class.section_records)
        qualified = "#{self.class.slug}:#{fingerprint}"
        return if user.suggestions.exists?(fingerprint: qualified)

        suggestion = user.suggestions.create!(
          watcher_slug: self.class.slug, fingerprint: qualified,
          title: title, body: body, kind: kind, action: action
        )
        suggestion.sections = sections
        suggestion
      end
  end
end
