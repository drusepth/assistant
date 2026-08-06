module Watcher
  # Superclass for watchers. A subclass declares the section slugs it
  # watches and implements `scan`, calling `propose` for anything worth the
  # user's attention. `propose` is fingerprint-deduped: a suggestion the
  # user dismissed (or already has) is never recreated, so re-running a
  # scan is always safe.
  class Base
    class_attribute :section_slugs, instance_accessor: false, default: []

    def self.slug = name.demodulize.underscore

    def initialize(user)
      @user = user
      @proposals = []
    end

    # Suggestions actually created by this scan (deduped ones excluded) —
    # what the notification fan-out speaks about.
    attr_reader :proposals

    def scan
      raise NotImplementedError
    end

    private
      attr_reader :user

      def propose(fingerprint:, title:, body: nil, kind: :nudge, action: {}, sections: self.class.section_slugs)
        scoped = "#{self.class.slug}/#{fingerprint}"
        return if user.suggestions.exists?(fingerprint: scoped)

        suggestion = user.suggestions.create!(
          watcher_slug: self.class.slug, fingerprint: scoped,
          title: title, body: body, kind: kind, action: action
        )
        suggestion.sections = Section.where(slug: sections)
        @proposals << suggestion
        suggestion
      end
  end
end
