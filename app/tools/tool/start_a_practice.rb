module Tool
  # Meditation, yoga, walks, journaling — the mind-body half of Health
  # (docs/HEALTH.md §6), riding the shared plan-tool contract. The brief
  # steers the same way start-a-hobby does, tuned for practices: tiny and
  # repeatable beats ambitious, frequency beats duration, and the first
  # session happens within days with nothing to buy.
  class StartAPractice < Base
    self.title = "Start a calm practice"
    self.description = "Meditation, yoga, a daily walk — a small steady practice, started this week."
    self.section_slugs = %w[ health ]
    self.kind = :plan

    input :practice, required: true,
      label: "What practice do you want to build?",
      hint: "“meditation”, “yoga”, “morning walks”, “journaling”."
    input :shape,
      label: "What can you give it?",
      hint: "Optional — “10 minutes before work”, “evenings, and my knees are bad”."

    BRIEF = <<~BRIEF.freeze
      This goal starts a calming mind-body practice. Optimize for tiny and
      repeatable, not ambitious: the first session happens within a day or two,
      lasts minutes not hours, and uses nothing they need to buy. Frequency
      beats duration — several short scheduled sessions across the first two
      weeks, building a rhythm before building length. Include one step that
      tries a free guided resource (a free app tier, a library video, a
      community class) without requiring any specific paid product. Keep the
      tone gentle: sessions are invitations, not obligations, and a missed day
      restarts nothing. If the practice is physical, early sessions stay easy
      and pain is a stop sign, not a challenge.
    BRIEF

    def call
      plan_goal!(
        title: "Build a #{inputs[:practice].to_s.squish} practice",
        brief: BRIEF,
        description: inputs[:shape].presence
      )
    end
  end
end
