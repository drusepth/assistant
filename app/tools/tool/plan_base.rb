module Tool
  # The plan-tool engine (the plan half of D19): a plan tool is goal capture
  # with framing. It creates a plain Goal and hands it to the same
  # Goals::BreakDown that plans every goal, passing a brief that shapes the
  # steps — no schema and no pipeline of its own, and everything it records
  # on the run is an ordinary primitive following ordinary rules. Situations
  # (D7) are exactly plan tools whose briefs span sections.
  class PlanBase < Base
    self.kind = :plan

    def call
      goal = record(user.goals.create!(title: goal_title, description: goal_description))

      begin
        Goals::BreakDown.new(goal: goal, profile: profile, brief: brief).plan!.each { |task| record(task) }
        # The plan is always findable where the tool lives, on top of
        # whatever the model filed it under.
        goal.sections = (goal.sections.to_a + self.class.section_records).uniq
      ensure
        # Stamp even on failure so the goal card can't spin forever — a
        # failed run leaves an ordinary unplanned goal the user can retry
        # from its own page, and the board refreshes either way.
        goal.update_column(:broken_down_at, Time.current)
        Turbo::StreamsChannel.broadcast_refresh_to(user, :tasks)
      end
    end

    private
      def goal_title = raise(NotImplementedError)
      def goal_description = nil
      def brief = self.class::BRIEF
  end
end
