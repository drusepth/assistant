module Watcher
  # The catch-all is telling you something (D-hobby-feeds §7 W5): when Other
  # Interests keeps filling with feeds about the same thing, that is a hobby
  # nobody has named yet. One nudge, whose accept opens Start-a-hobby
  # prefilled — the agent proposes, the user disposes (D20), and the lens is
  # created by the tool the user ran, never by a watcher and never by a
  # model's answer.
  #
  # The spotting itself moved to `Hobbies::Spotter` (D-hobby-spotting), which
  # this shares with the hub's suggestion chips: one model call per scan
  # feeds both the quiet surface (chips in "Add another hobby") and the loud
  # one (this nudge). What stays here is the loudness policy — one pending
  # nudge at a time, monthly fingerprint, dismissal quiets the name for the
  # rest of the month.
  #
  # It remains one of the watchers allowed off the SQL-only leash, for the
  # same reason as job_scout (D-career-web) and under the same discipline:
  # "these four feeds are all about birding" is not a question SQL can
  # answer, and the earlier design that tried — keyword matching against a
  # per-hobby vocabulary — was cut because enumerating the topic space is a
  # promise this codebase can't keep. The call is cheap and rare: a handful
  # of *feeds*, not the story firehose.
  class HobbyFromFeeds < Base
    self.section_slugs = %w[ hobbies ]

    MAX_PENDING = 1

    # The name's monthly bucket, the goal-stall convention: a dismissal
    # quiets this hobby for the rest of the month, then it may fairly
    # return. The chips read the same fingerprint, so saying "no" once says
    # it to both surfaces.
    def self.bucket_for(name, on: Date.current)
      "hobby:#{name.parameterize}/#{on.strftime("%Y-%m")}"
    end

    # The same string as `Base#propose` stores, so a surface that wants to
    # know whether this name was turned down can ask for it by name.
    def self.fingerprint_for(name, on: Date.current) = "#{slug}/#{bucket_for(name, on: on)}"

    def scan
      # The scan runs whatever is pending: the chips want a fresh reading of
      # the catch-all every time, and the nudge is the loud subset of it.
      candidates = ::Hobbies::Spotter.call(user)
      return if user.suggestions.actionable.where(watcher_slug: self.class.slug).count >= MAX_PENDING

      candidates.first(MAX_PENDING).each do |candidate|
        propose(
          fingerprint: self.class.bucket_for(candidate.name),
          title: "Looks like #{candidate.name} is a thing",
          body: "#{candidate.reason} Naming it as a hobby files those feeds under it — and gives it a page, " \
            "a calendar, and somewhere for the projects to live.",
          action: { "tool" => { "slug" => "start_a_hobby", "inputs" => { "hobby" => candidate.name } },
                    "accept_label" => "Start #{candidate.name}" }
        )
      end
    end
  end
end
