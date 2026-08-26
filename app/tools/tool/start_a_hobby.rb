module Tool
  # The Hobbies front door (docs/HOBBIES.md): turn curiosity into a first
  # taste. Creates the hobby's lens (D25) and rides the shared plan-tool
  # contract — the brief steers hard toward doing the hobby cheaply within
  # days, against the two classic ways starting dies: gear acquisition and
  # endless research.
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
      # The lens exists before the model call, so the breakdown can file
      # steps under it too.
      lens = Hobbies::Lens.find_or_create!(inputs[:hobby])
      # The nudge's accept lands here (D-hobby-spotting), so this is where
      # the feeds it was spotted from get claimed — "naming it files those
      # feeds under it" is a promise the suggestion's body makes.
      Hobbies::Spotter.claim!(user, lens)
      # A hobby is still a question about the feeds already followed
      # (D-hobby-feeds §4) — the same one the add tile asks, since a hobby
      # can start here.
      Hobbies::MapFeeds.enqueue(user, [ lens ])
      goal = plan_goal!(title: "Get into #{lens.name}", brief: BRIEF, description: inputs[:about].presence)
      goal.sections = (goal.sections.to_a + [ lens ]).uniq
    end
  end
end
