module Tool
  # The first plan tool (M2.2), proving the plan half of the D19 contract —
  # now the simplest rider on PlanBase: a title, two inputs, and a brief.
  class LearnSomething < PlanBase
    self.title = "Learn something"
    self.description = "Name a topic — get a paced study plan of day-sized steps."
    self.section_slugs = %w[ education ]

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

    private
      def goal_title = "Learn #{inputs[:topic].to_s.strip}"
      def goal_description = inputs[:angle].presence
  end
end
