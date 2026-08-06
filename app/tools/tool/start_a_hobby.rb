module Tool
  # The Hobbies front door (docs/HOBBIES.md): turn curiosity into a first
  # taste. Creates the hobby's lens (D21) and rides the shared breakdown
  # pipeline like every plan tool — the brief steers hard toward doing the
  # hobby cheaply within days, against the two classic ways starting dies:
  # gear acquisition and endless research.
  class StartAHobby < Base
    self.title = "Start a hobby"
    self.description = "Curious about something? Get a cheap first taste on the calendar this week."
    self.section_slugs = %w[ hobbies ]
    self.kind = :plan

    input :hobby, required: true, label: "What are you curious about?"
    input :about,
      label: "Anything that shapes it",
      hint: "Optional — budget, space, time, why now."

    BRIEF = <<~BRIEF.freeze
      This goal is about starting a brand-new hobby. Optimize for the cheapest,
      fastest first taste, not mastery: the first step has them doing the hobby
      within days using things they already have or can borrow — never "research
      gear" or a shopping list first. Include one step that tries the hobby for
      real, one tiny finishable first project, and one step about finding other
      people who do it (a club, class, or community to check out). Buying
      anything appears at most once, late, and as cheap as possible.
    BRIEF

    def call
      lens = Hobbies::Lens.find_or_create!(inputs[:hobby])
      goal = record(user.goals.create!(title: "Get into #{lens.name}", description: inputs[:about].presence))

      begin
        Goals::BreakDown.new(goal: goal, profile: profile, brief: BRIEF).plan!.each { |task| record(task) }
        # Filed under Hobbies and the hobby's own lens (created before the
        # model call, so steps can be filed under it too), on top of
        # whatever else the model chose.
        goal.sections = (goal.sections.to_a + self.class.section_records + [ lens ]).uniq
      ensure
        goal.update_column(:broken_down_at, Time.current)
        Turbo::StreamsChannel.broadcast_refresh_to(user, :tasks)
      end
    end
  end
end
