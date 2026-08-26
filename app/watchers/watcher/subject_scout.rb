module Watcher
  # Suggested subjects from the other lenses (docs/EDUCATION_PLAN.md §7):
  # the payoff of lens-over-primitives — the app already knows the hobbies,
  # so it can say what's worth learning and *why*, reason printed on the
  # card. Deterministic candidates from the affinity map first; the model
  # extension covers only the lenses the map doesn't know, on the job_scout
  # precedent (one call, propose-don't-dispose, D20 write surface intact).
  # Filed sectionless on purpose: these render in the hub's begin zone and
  # the Dashboard feed, not doubled into the Attend zone.
  class SubjectScout < Base
    self.section_slugs = %w[ education ]

    MAX_MODEL_PICKS = 2

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the subject-scout feature of a private, self-hosted personal
      school. For each numbered hobby, say what subject it makes worth
      studying — the way theatre argues for rhetoric or skateboarding for the
      physics of motion. Respond with a JSON object:
      {"picks": [{"index": 0, "subject": "...", "reason": "..."}, ...]}.
      At most #{MAX_MODEL_PICKS} picks; each reason is one warm line naming the hobby.
      An empty list is right when nothing genuinely follows — a stretched
      suggestion costs trust.
    PROMPT

    def scan
      unmapped = []
      active_lenses.each do |lens|
        if (entry = Education::Affinities.for(lens.name))
          suggest(lens, entry.subject, entry.reason)
        else
          unmapped << lens
        end
      end
      model_extension(unmapped)
    end

    private
      # A lens counts as the user's when something of *theirs* lives in it —
      # a spouse's hobby is not this learner's signal.
      def active_lenses
        lenses = Section.find_by(slug: "hobbies")&.children || Section.none
        lenses.select { |lens| lens_used?(lens) }
      end

      def lens_used?(lens)
        [ Task, Event, Note, Document, Goal, Photo, Recipe, Subject ].any? do |model|
          model.where(user: user).in_section(lens).exists?
        end
      end

      def suggest(lens, subject_title, reason)
        return if already_studying?(subject_title)

        propose(
          # One per lens+subject, ever — a dismissal is an answer.
          fingerprint: "lens:#{lens.slug}/#{subject_title.parameterize}",
          title: "Worth studying: #{subject_title}",
          body: "Because of your #{lens.name} lens. #{reason}",
          kind: :insight,
          action: { "tool" => { "slug" => "learn_something",
                                "inputs" => { "topic" => subject_title,
                                              "angle" => "I got here from my #{lens.name} hobby — teach it through that where it helps" } } },
          sections: []
        )
      end

      def already_studying?(subject_title)
        user.subjects.where("LOWER(title) LIKE ?", "%#{Subject.sanitize_sql_like(subject_title.downcase)}%").exists?
      end

      # The lenses the map doesn't know, ranked by the household's model —
      # optional garnish over the same write surface, skipped entirely on a
      # box with no model configured.
      def model_extension(lenses)
        return if lenses.empty?

        profile = user.household.model_profile
        return unless profile&.configured?

        listing = lenses.each_with_index.map { |lens, index| "#{index}. #{lens.name}" }.join("\n")
        response = profile.client.chat(
          [ { role: "system", content: SYSTEM_PROMPT }, { role: "user", content: listing } ], json: true
        )
        Array(response["picks"]).first(MAX_MODEL_PICKS).each do |pick|
          next unless pick.is_a?(Hash) && pick["subject"].present?

          lens = lenses[pick["index"].to_i]
          suggest(lens, pick["subject"].to_s, pick["reason"].to_s) if lens
        end
      rescue Llm::Error
        # Garnish never breaks the scan; the map's suggestions already stand.
        nil
      end
  end
end
