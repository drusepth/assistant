module Dashboard
  # The dashboard hub board: one card per enabled life area, each carrying
  # the few things in that area that actually want the user today.
  #
  # Sections are lenses, not silos, so an item tagged Health + People shows
  # on both cards — that duplication is the point. The card is a doorway to
  # the section hub, and it should look like whatever the hub would show.
  #
  # Busy areas earn a wide card with task rows; quiet areas collapse to a
  # narrow one with a single honest line. Everything reads through
  # visible_to (D9), and every count is computed here rather than in the
  # view, so the board's editorial rules live in one place.
  class Board
    # How many task rows a wide card shows before it stops listing them.
    ROWS = 3
    # Areas with at least this many open items get the wide treatment.
    WIDE_THRESHOLD = 2

    Card = Struct.new(:section, :tasks, :next_event, :open_count, :overdue_count, keyword_init: true) do
      # Wide cards list rows; narrow ones state a single line.
      def wide? = open_count >= WIDE_THRESHOLD

      def quiet? = open_count.zero? && next_event.nil?

      # The count line in the card's header — "4 open · 1 overdue", or the
      # one-word state of an area with nothing in it.
      def status
        return "Clear" if quiet?

        parts = []
        parts << "#{open_count} open" if open_count.positive?
        parts << "#{overdue_count} overdue" if overdue_count.positive?
        parts << "1 upcoming" if parts.empty? && next_event
        parts.join(" · ")
      end

      # A narrow card has no room for rows, so it says the single most
      # useful thing instead: the soonest task, else the next event.
      def headline
        return tasks.first.title if tasks.any?
        return next_event.title if next_event

        "Nothing due"
      end
    end

    def initialize(viewer)
      @viewer = viewer
    end

    def cards
      @cards ||= sections.map { |section| build_card(section) }
    end

    # Wide cards first so the grid fills top-heavy, then narrow ones, with
    # quiet areas sinking to the bottom. Within a tier, the area with the
    # most overdue work leads.
    def sorted_cards
      cards.sort_by { |card| [ card.quiet? ? 1 : 0, -card.overdue_count, -card.open_count, card.section.name ] }
    end

    private
      attr_reader :viewer

      # The board cards top-level areas only — subsections are a detail of
      # the hub page, not the front door.
      def sections
        @sections ||= viewer.enabled_sections.reject(&:parent_id)
      end

      # An item tagged only "Money · Subscriptions" belongs on the Money
      # card: taggings are collected against every enabled section, then
      # rolled up to the top-level area the card represents.
      def rollup
        @rollup ||= sections.each_with_object({}) do |section, map|
          map[section.id] = section.id
          section.children.each { |child| map[child.id] = section.id }
        end
      end

      def tagged_section_ids = rollup.keys

      def build_card(section)
        section_tasks = tasks_by_section.fetch(section.id, [])

        Card.new(
          section: section,
          tasks: section_tasks.first(ROWS),
          next_event: events_by_section[section.id],
          open_count: section_tasks.size,
          overdue_count: section_tasks.count { |task| task.due_on&.before?(Date.current) }
        )
      end

      # One query for every card's rows. Undated tasks sort last: a card
      # leads with what has a deadline attached. A task tagged both "Money"
      # and "Money · Subscriptions" rolls up to one card and must count
      # once, so rows are uniqued per card after the rollup.
      def tasks_by_section
        @tasks_by_section ||= Task.visible_to(viewer).open
          .joins(:section_taggings)
          .where(section_taggings: { section_id: tagged_section_ids })
          .includes(:sections, :goal)
          .select("tasks.*", "section_taggings.section_id AS carded_section_id")
          .sort_by { |task| [ task.due_on ? 0 : 1, task.due_on || Date.current ] }
          .group_by { |task| rollup.fetch(task.carded_section_id) }
          .transform_values { |tasks| tasks.uniq(&:id) }
      end

      def events_by_section
        @events_by_section ||= Event.visible_to(viewer).upcoming
          .joins(:section_taggings)
          .where(section_taggings: { section_id: tagged_section_ids })
          .select("events.*", "section_taggings.section_id AS carded_section_id")
          .each_with_object({}) do |event, map|
            card_id = rollup.fetch(event.carded_section_id)
            map[card_id] ||= event
          end
      end
  end
end
