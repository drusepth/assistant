module Sections
  # Per-section engagement signal for browse grids — hobby cards and the
  # seeded-subsection tiles on Money/Rights: what's planned next and how
  # much is in flight, so each doorway carries pull rather than a bare
  # name. Batched — one query per primitive, not per section — and
  # everything goes through visible_to (D9).
  class Summary
    Row = Struct.new(:section, :next_event, :open_tasks_count, :active_goals_count, keyword_init: true) do
      def quiet?
        next_event.nil? && open_tasks_count.zero? && active_goals_count.zero?
      end
    end

    class << self
      def for(viewer, sections)
        section_ids = sections.map(&:id)
        return [] if section_ids.empty?

        tasks = counts_by_section(Task.visible_to(viewer).open, section_ids)
        goals = counts_by_section(Goal.visible_to(viewer).active, section_ids)
        events = next_event_by_section(viewer, section_ids)

        sections.map do |section|
          Row.new(
            section: section,
            next_event: events[section.id],
            open_tasks_count: tasks.fetch(section.id, 0),
            active_goals_count: goals.fetch(section.id, 0)
          )
        end
      end

      private

      def counts_by_section(scope, section_ids)
        scope.joins(:section_taggings)
          .where(section_taggings: { section_id: section_ids })
          .group("section_taggings.section_id").count
      end

      def next_event_by_section(viewer, section_ids)
        Event.visible_to(viewer).upcoming
          .joins(:section_taggings)
          .where(section_taggings: { section_id: section_ids })
          .select("events.*", "section_taggings.section_id AS summarized_section_id")
          .each_with_object({}) { |event, map| map[event.summarized_section_id] ||= event }
      end
    end
  end
end
