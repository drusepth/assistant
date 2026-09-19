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

    # The inverse of `propose` (D-suggestion-lifecycle): has the world
    # handled what this suggestion was about? A watcher that answers gets a
    # retire pass after its scan; the default false means every watcher
    # keeps its existing behavior until it opts in.
    #
    # The answer is the watcher's own signal, inverted, in SQL — never a
    # model call, and never anything that writes. It runs against
    # suggestions that may be months old, so it must tolerate a subject that
    # has since been deleted (`find_by`, not `find`) and treat a vanished
    # subject as resolved: there is nothing left to nudge about.
    def resolved?(suggestion)
      false
    end

    # Whether this watcher answers `resolved?` at all. The scan skips the
    # retire pass — and its query — for the ones that don't, so opting in is
    # what costs something and staying out costs nothing.
    def self.retires? = instance_method(:resolved?).owner != Watcher::Base

    # The user waved this one away (D-event-radar §5.4). A watcher whose
    # proposals rest on a judgment it can be corrected on — the event radar
    # rejecting the match behind a dismissed nudge, so the title comes back
    # as an example — answers here; the default is nothing, so every other
    # watcher keeps today's behavior. Never a model call, never a proposal.
    def dismissed(suggestion)
    end

    private
      attr_reader :user

      # Watchers name their subject inside the fingerprint (`event:42`,
      # `goal:7`, `person:3`) so the retire pass can find it again without a
      # second column — the fingerprint was always the subject key, and
      # `resolved?` is just the first reader that needs it back.
      #
      # nil means the fingerprint names no subject we recognize — an older
      # row from before the watcher's format changed, say. Callers must read
      # that as "can't say", never as "handled": a subject we failed to
      # parse is not evidence the world did anything, and retiring on it
      # would quietly delete live nudges the day a fingerprint format moved.
      def subject_id(suggestion, prefix)
        suggestion.fingerprint[/\b#{Regexp.escape(prefix)}:(\d+)/, 1]&.to_i
      end

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
