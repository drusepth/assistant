module Watcher
  # The agent asking about itself (D-agent-earned-dials). Onboarding
  # deliberately never offers Active — a first-run user has no basis to want
  # daily notifications from an app that hasn't shown them anything — and
  # its copy promises "flip it on whenever the app has earned it." This
  # watcher is the app noticing that it has, or hasn't.
  #
  # Two symmetric offers, both model-free, both settled by one click:
  # upgrade a section whose suggestions the user actually uses, and pipe
  # down in one where they're dismissed on sight. The dial only ever moves
  # on an accept — D20 applies to the agent's own volume as much as to
  # anything else it proposes.
  #
  # Sectionless, so it runs at the Quiet default on the weekly scan: an
  # offer to be louder that arrived daily would be answering its own
  # question.
  class DialTuner < Base
    self.section_slugs = []

    USED_WINDOW = 90.days
    USED_THRESHOLD = 3

    IGNORED_WINDOW = 6.months
    IGNORED_RUN = 6

    QUIETER = { "active" => "quiet", "quiet" => "off" }.freeze

    def scan
      Section.top_level.each do |section|
        next unless user.section_enabled?(section)

        case user.agent_level_for(section)
        when "quiet" then offer_upgrade(section) || offer_quieter(section)
        when "active" then offer_quieter(section)
        end
      end
      proposals
    end

    # The offer stops applying once the dial has moved — by this suggestion
    # or by the user going to Settings themselves. Either way the question
    # has been answered and should stop being asked.
    def resolved?(suggestion)
      wanted = suggestion.action.dig("agent_level", "level")
      section = Section.find_by(slug: suggestion.action.dig("agent_level", "section"))
      return true if section.nil? || wanted.blank?

      user.agent_level_for(section) == wanted
    end

    private
      def offer_upgrade(section)
        return if used(section) < USED_THRESHOLD

        propose(
          # Once ever, per section: a dismissal is a permanent answer, and
          # that permanence is what makes the offer polite rather than a
          # campaign.
          fingerprint: "upgrade/#{section.slug}",
          kind: :insight,
          title: "Want me to keep a closer eye on #{section.name}?",
          body: "You've acted on #{used(section)} of my #{section.name} suggestions lately. " \
                "I can check daily instead of weekly, and send them to your phone if you've set that up.",
          action: level_action(section, "active", "Check daily"),
          sections: [ section.slug ]
        )
      end

      def offer_quieter(section)
        return unless ignored?(section)
        return unless (quieter = QUIETER[user.agent_level_for(section)])

        propose(
          # Bucketed by year rather than once-ever: going quieter must stay
          # easy to reach, so the offer may come back — but not twice in a
          # year, which would be nagging about nagging.
          fingerprint: "quieter/#{section.slug}/#{Date.current.year}",
          kind: :insight,
          title: "Should I stop bringing up #{section.name}?",
          body: "You've passed on my last #{IGNORED_RUN} #{section.name} suggestions. " \
                "That's a fair answer — I can #{quieter == "off" ? "stop entirely" : "speak up less often"}.",
          action: level_action(section, quieter, quieter == "off" ? "Stop these" : "Less often"),
          sections: [ section.slug ]
        )
      end

      def level_action(section, level, label)
        { "agent_level" => { "section" => section.slug, "level" => level }, "accept_label" => label }
      end

      def used(section)
        (@used ||= {})[section.id] ||=
          scoped(section).accepted.where(created_at: USED_WINDOW.ago..).count
      end

      # A run of dismissals with nothing accepted behind it. Both halves
      # matter: six dismissals after an acceptance is someone using the
      # feature and declining six things, not someone tired of hearing from
      # it. Suggestions the world retired (`resolved`) are excluded on the
      # same logic — that is the app being right, not being ignored.
      def ignored?(section)
        decided = scoped(section).where(status: %i[ accepted dismissed ])
          .where(created_at: IGNORED_WINDOW.ago..).order(created_at: :desc).limit(IGNORED_RUN)

        decided.size >= IGNORED_RUN && decided.all?(&:dismissed?)
      end

      # The dial tuner's own suggestions are excluded from both counts: an
      # offer to be quieter that the user ignored must not become evidence
      # that they want it quieter still.
      def scoped(section)
        user.suggestions.in_section(section).where.not(watcher_slug: self.class.slug)
      end
  end
end
