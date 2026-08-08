module Hobbies
  # Per-lens engagement signal for the Hobbies page grid: what's planned
  # next and how much is in flight, so each card is a doorway with pull
  # rather than a bare name. Batched — one query per primitive, not per
  # lens — and everything goes through visible_to (D9).
  class LensSummary
    Summary = Struct.new(:lens, :next_event, :open_tasks_count, :active_goals_count, keyword_init: true) do
      def quiet?
        next_event.nil? && open_tasks_count.zero? && active_goals_count.zero?
      end
    end

    class << self
      def for(viewer, lenses)
        lens_ids = lenses.map(&:id)
        return [] if lens_ids.empty?

        tasks = counts_by_lens(Task.visible_to(viewer).open, lens_ids)
        goals = counts_by_lens(Goal.visible_to(viewer).active, lens_ids)
        events = next_event_by_lens(viewer, lens_ids)

        lenses.map do |lens|
          Summary.new(
            lens: lens,
            next_event: events[lens.id],
            open_tasks_count: tasks.fetch(lens.id, 0),
            active_goals_count: goals.fetch(lens.id, 0)
          )
        end
      end

      private

      def counts_by_lens(scope, lens_ids)
        scope.joins(:section_taggings)
          .where(section_taggings: { section_id: lens_ids })
          .group("section_taggings.section_id").count
      end

      def next_event_by_lens(viewer, lens_ids)
        Event.visible_to(viewer).upcoming
          .joins(:section_taggings)
          .where(section_taggings: { section_id: lens_ids })
          .select("events.*", "section_taggings.section_id AS lens_id")
          .each_with_object({}) { |event, map| map[event.lens_id] ||= event }
      end
    end
  end
end
