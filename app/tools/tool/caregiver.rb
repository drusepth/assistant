module Tool
  # The caregiving Situation (D7, docs/PEOPLE.md §4): becoming responsible
  # for an aging parent or sick family member — the heaviest coordination
  # load a household absorbs, and the one the wealthy hand to care managers.
  # A plan tool with a rich cross-section brief, nothing more.
  class Caregiver < Base
    self.title = "Becoming a caregiver"
    self.description = "Taking on care for a parent or family member — records, appointments, benefits, and staying afloat."
    self.section_slugs = %w[ people health money ]
    self.kind = :plan

    input :who, required: true,
      label: "Who are you caring for?",
      hint: "“my mom”, “my husband”, “Aunt Rosa”."
    input :situation,
      label: "What's going on?",
      hint: "Optional — a diagnosis, a fall, memory slipping, just aging…"
    input :details,
      label: "Anything else?",
      hint: "Optional — siblings involved, how far away they live, your work situation…"

    BRIEF = <<~BRIEF.freeze
      This goal is becoming a caregiver for a family member — a Situation that
      spans several life areas, so spread the steps' sections accordingly:
      - The picture (health): one step to write down the current state — the
        diagnoses, doctors, medications as known — as a note to build on. Add
        the person's regular appointments to the calendar as they're learned.
      - Paperwork that unlocks everything else (health/rights): getting listed
        as an authorized contact with doctors (HIPAA release), and finding out
        whether powers of attorney / advance directives exist — as
        find-out-and-ask steps with [BRACKETED PLACEHOLDERS], never legal
        advice.
      - Money (money): what care costs and what helps pay — a step to check
        benefit eligibility (the app's Benefits screener under Money can run
        this), and one to locate the person's insurance cards and statements
        into the document vault.
      - The village (people): who else helps — a step to talk with siblings or
        other family about splitting duties, and one to identify the backup
        person for when the user is unavailable.
      - Staying afloat (people/health): caregiving is a marathon; include one
        recurring-shaped step for respite — a standing break, a caregiver
        support group to find locally (never invent a specific organization).
      Pace the steps over weeks, not days — two or three concrete things at a
      time. Nothing about this plan should read as urgent-alarm; steady beats
      frantic.
    BRIEF

    def call
      plan_goal!(title: "Care for #{inputs[:who].to_s.strip}", brief: BRIEF, description: description_text)
    end

    private
      def description_text
        [ inputs[:situation].presence && "Situation: #{inputs[:situation]}",
          inputs[:details].presence ].compact.join("\n").presence
      end
  end
end
