module Tool
  # The first plan tool (M2.2), proving the plan half of the D19 contract.
  # Architecture note: a plan tool adds no schema and no pipeline of its
  # own — it is goal capture with framing. It creates a plain Goal and
  # hands it to the same Goals::BreakDown that plans every goal, passing a
  # brief that shapes the steps; everything it records on the run is an
  # ordinary primitive following ordinary rules.
  class LearnSomething < Base
    self.title = "Learn something"
    self.description = "Name a topic — get a paced study plan of day-sized steps."
    self.section_slugs = %w[ education ]
    self.kind = :plan

    input :topic, required: true, label: "What do you want to learn?"
    input :angle,
      label: "Your level, goal, or deadline",
      hint: "Optional — “complete beginner”, “conversational by June”, “for a career switch”."

    BRIEF = <<~BRIEF.freeze
      This goal is a personal study plan. Structure the steps as a progression:
      start from orientation and fundamentals, alternate learning with hands-on
      practice, and end with a step where the learner produces or does something
      that proves it stuck. Each step names concrete material or an exercise —
      never "study more" or "keep practicing".
    BRIEF

    def call
      plan_goal!(title: goal_title, brief: BRIEF, description: inputs[:angle].presence)
    end

    private
      def goal_title = "Learn #{inputs[:topic].to_s.strip}"
  end
end
