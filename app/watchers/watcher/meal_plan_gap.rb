module Watcher
  # The coming week is mostly unplanned, in a kitchen that plans
  # (docs/FOOD_PLAN.md §6). Off until the household has planned meals in two
  # different weeks — this is never a nag for people who don't plan.
  class MealPlanGap < Base
    self.section_slugs = %w[ food ]

    NIGHTS = 7
    ENOUGH = 3
    PLANNING_WEEKS = 2

    def scan
      Kitchen.visible_to(user).find_each do |kitchen|
        next unless plans?(kitchen)

        range = Date.current..(Date.current + NIGHTS - 1)
        planned = kitchen.meals.between(range).where(slot: "dinner").distinct.count(:date)
        next if planned >= ENOUGH

        propose_for(kitchen, NIGHTS - planned)
      end
      proposals
    end

    private
      def plans?(kitchen)
        kitchen.meals.where(date: ...Date.current).pluck(:date).map(&:beginning_of_week).uniq.size >= PLANNING_WEEKS
      end

      def propose_for(kitchen, free)
        ready = Kitchens::Ideas.new(kitchen, user).ready_to_make.count(&:ready?)
        body = "#{free} nights have nothing planned."
        body += " #{ready == 1 ? "One dish is" : "#{ready} dishes are"} ready to make from what's in." if ready.positive?

        propose(
          fingerprint: "kitchen:#{kitchen.id}/week:#{Date.current.beginning_of_week.iso8601}",
          title: "This week's dinners aren't planned yet",
          body: body,
          action: { "path" => "/kitchens/#{kitchen.id}/plan", "accept_label" => "Plan the week",
                    "expires_on" => Date.current.end_of_week.iso8601 }
        )
      end
  end
end
