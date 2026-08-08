module Tool
  # The bereavement Situation (D7, docs/PEOPLE.md §4): the life event
  # nobody can think straight through, which is exactly when a quiet list
  # of what actually needs doing — and what can wait — is worth the most.
  # A plan tool whose brief is mostly about tone and pace.
  class Bereavement < Base
    self.title = "After a loss"
    self.description = "When someone dies, a quiet list of what needs doing — and what can wait."
    self.section_slugs = %w[ people money rights ]
    self.kind = :plan

    input :who, required: true,
      label: "Who did you lose?",
      hint: "However you'd say it — “my dad”, “Grandma June”."
    input :details,
      label: "Anything that shapes what needs doing?",
      hint: "Optional — “I'm the executor”, “she lived alone out of state”, “no will that I know of”."

    BRIEF = <<~BRIEF.freeze
      This goal is navigating the weeks after a family member's death. The
      user is grieving; the plan's job is to hold the list so they don't have
      to. Tone and pacing rules come first:
      - Calm, plain, warm. No productivity cheer, no exclamation points, no
        "checklist" energy. Steps read like a steady friend's reminders.
      - Very few steps due soon; most of this can wait longer than it feels
        like it can. Spread steps over weeks and say so in their titles where
        it helps ("when you're ready…").
      What belongs in the plan, spread across sections:
      - Soon (people/rights): telling the people who need to know — the app's
        "What do I say?" tool can help with those messages; obtaining several
        certified copies of the death certificate (many offices want originals).
      - Notifications that stop things (money): employer and benefits,
        Social Security or pension if applicable, banks and card issuers,
        recurring bills and subscriptions in the person's name — as
        find-and-notify steps with [BRACKETED PLACEHOLDERS] for what's unknown.
      - The estate (rights): locating the will and key documents into the
        vault; whether probate applies is a question for the county or a
        lawyer — frame it as a find-out step, never legal advice.
      - The human side (people): one step about accepting offered help
        concretely, and one about a remembrance when the time is right.
      Include only what fits the user's details; an executor's list differs
      from a grandchild's.
    BRIEF

    def call
      plan_goal!(title: "After losing #{inputs[:who].to_s.strip}", brief: BRIEF, description: inputs[:details].presence)
    end
  end
end
