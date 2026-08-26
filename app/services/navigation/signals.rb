module Navigation
  # What's actually behind each door in the rail, in one short string per row.
  #
  # A nav tooltip has exactly two audiences and taxonomy serves neither: with
  # the rail expanded the label is already two inches to the left, and with it
  # collapsed the only question worth answering on hover is "is there anything
  # in there for me right now?". So these signals carry *state* — the same
  # vocabulary the hub cards settled on: a date beats a count, a count beats
  # nothing, and nothing renders as nothing rather than as a filler line.
  #
  # Built once per render (the rail is on every page), so everything here is
  # batched or memoized and nothing runs for a row the rail didn't draw.
  # Everything reads through visible_to (D9).
  class Signals
    include ActionView::Helpers::TextHelper
    include ActionView::Helpers::NumberHelper
    include ActionView::Helpers::DateHelper

    # `badge` is the chip beside the body: reserved for a state that wants
    # doing something about, never for a category name.
    Signal = Data.define(:body, :badge)

    # What counts as "new" in a vault pile.
    RECENT_WINDOW = 7.days

    def initialize(viewer)
      @viewer = viewer
    end

    # The fixed rows, by the name the rail draws them under. Passwords and
    # Diary are deliberately absent: they are sealed containers
    # (D-passwords-vault, D-diary-vault), and a hover must not leak how much
    # is inside one.
    def row(name)
      case name
      when "Dashboard" then dashboard
      when "Today" then today
      when "Calendar" then calendar
      when "Tasks" then tasks
      when "Conversations" then conversations
      when "Address Book" then address_book
      when "Photos" then pile(Photo.visible_to(@viewer), "photo")
      when "Recipes" then pile(Recipe.visible_to(@viewer), "recipe")
      when "Documents" then pile(Document.visible_to(@viewer), "file")
      when "Notes" then pile(Note.visible_to(@viewer), "note")
      when "Mail" then mail
      end
    end

    # A life-lens row: what's next in that lens, else what's in flight there.
    def section(section)
      summary = summaries[section.id]
      return nil unless summary

      body = section_body(summary)
      badge = "Overdue" if overdue_by_section.fetch(section.id, 0).positive?
      return nil unless body || badge

      Signal.new(body: body, badge: badge)
    end

    # The lenses the rail draws, loaded once: the layout iterates this rather
    # than asking the user again, so the list and the signals over it cost a
    # single trip between them.
    def sections = @sections ||= @viewer.enabled_sections

    private
      def section_body(summary)
        if summary.next_event
          "#{summary.next_event.title} · #{when_phrase(summary.next_event)}"
        elsif !summary.quiet?
          in_flight = []
          in_flight << pluralize(summary.open_tasks_count, "open task") if summary.open_tasks_count.positive?
          in_flight << pluralize(summary.active_goals_count, "project") if summary.active_goals_count.positive?
          in_flight.join(" · ")
        end
      end

      # The dashboard is a synthesis across lenses, so its signal counts
      # lenses rather than items — and it reuses the per-section data already
      # loaded for the rows below it, so it costs no query of its own.
      def dashboard
        count = summaries.values.count do |summary|
          overdue_by_section.key?(summary.section.id) || summary.next_event&.starts_at&.to_date == Date.current
        end
        return nil if count.zero?

        Signal.new(body: "#{pluralize(count, "area")} #{count == 1 ? "needs" : "need"} attention", badge: nil)
      end

      def today
        parts = []
        parts << "#{task_buckets.fetch("overdue", 0)} overdue" if task_buckets.fetch("overdue", 0).positive?
        parts << "#{task_buckets.fetch("today", 0)} due today" if task_buckets.fetch("today", 0).positive?
        parts << pluralize(events_today, "event") if events_today.positive?
        return nil if parts.empty?

        Signal.new(body: parts.join(" · "), badge: task_buckets.key?("overdue") ? "Overdue" : nil)
      end

      def calendar
        event = Event.visible_to(@viewer).upcoming.first
        return nil unless event

        Signal.new(body: "Next: #{event.title} · #{when_phrase(event)}", badge: nil)
      end

      # The board, not the agenda: the whole open pile and the part of it
      # nobody has picked a day for, which is what the Tasks page is for.
      def tasks
        open = task_buckets.values.sum
        return nil if open.zero?

        parts = [ "#{open} open" ]
        parts << "#{task_buckets["none"]} unscheduled" if task_buckets.fetch("none", 0).positive?
        Signal.new(body: parts.join(" · "), badge: task_buckets.key?("overdue") ? "Overdue" : nil)
      end

      def conversations
        run = @viewer.tool_runs.where(tool_slug: Tool.chat_slugs)
          .order(Arel.sql("(SELECT MAX(m.id) FROM tool_run_messages m WHERE m.tool_run_id = tool_runs.id) DESC"))
          .order(created_at: :desc)
          .includes(:subject)
          .first
        return nil unless run

        title = run.subject&.try(:title).presence || run.tool.title
        last_at = run.tool_run_messages.maximum(:created_at) || run.created_at
        Signal.new(body: "Last: #{title} · #{time_ago_in_words(last_at)} ago", badge: nil)
      end

      # The circle is the bounded half of the address book, which is why the
      # birthday scan runs over it and not over every contact with a birthday.
      def address_book
        people = Person.visible_to(@viewer)
        total = people.count
        return nil if total.zero?

        parts = [ "#{number_with_delimiter(total)} #{"contact".pluralize(total)}" ]
        birthdays = people.circle.birthday_within(RECENT_WINDOW.in_days.to_i).size
        parts << "#{birthdays} #{"birthday".pluralize(birthdays)} this week" if birthdays.positive?
        Signal.new(body: parts.join(" · "), badge: nil)
      end

      def mail
        scope = EmailMessage.where(user_id: @viewer.id).inbound.live
        unread = scope.where(seen: false).count
        needs_action = scope.where("json_extract(triage, '$.category') = 'action_needed'").count
        return nil if unread.zero? && needs_action.zero?

        parts = []
        parts << "#{number_with_delimiter(unread)} unread" if unread.positive?
        parts << "#{needs_action} #{needs_action == 1 ? "needs" : "need"} action" if needs_action.positive?
        Signal.new(body: parts.join(" · "), badge: needs_action.positive? ? "Needs action" : nil)
      end

      # A vault pile: how much is in there, and what landed this week — the
      # recency is the half that changes, and so the half worth a hover.
      #
      # One query, two numbers: grouping on the boolean splits the table into
      # old and new buckets in a single pass, rather than two COUNT(*) walks
      # over the same rows on every page render.
      def pile(scope, noun)
        cutoff = ApplicationRecord.sanitize_sql_array(
          [ "#{scope.table_name}.created_at >= ?", RECENT_WINDOW.ago ]
        )
        buckets = scope.group(Arel.sql(cutoff)).count
        total = buckets.values.sum
        return nil if total.zero?

        recent = buckets.sum { |new_arrival, count| truthy?(new_arrival) ? count : 0 }
        body = "#{number_with_delimiter(total)} #{noun.pluralize(total)}"
        body += " · #{recent} this week" if recent.positive?
        Signal.new(body: body, badge: nil)
      end

      # SQLite hands the grouped boolean back as 1/0; another adapter may
      # hand back true/false.
      def truthy?(value) = value == true || value == 1

      def summaries
        @summaries ||= Sections::Summary.for(@viewer, sections).index_by { |row| row.section.id }
      end

      def overdue_by_section
        @overdue_by_section ||= Task.visible_to(@viewer).open
          .where(due_on: ...Date.current)
          .joins(:section_taggings)
          .where(section_taggings: { section_id: sections.map(&:id) })
          .group("section_taggings.section_id").count
      end

      def task_buckets
        @task_buckets ||= begin
          bucket = ApplicationRecord.sanitize_sql_array([
            "CASE WHEN tasks.due_on IS NULL THEN 'none' " \
            "WHEN tasks.due_on < ? THEN 'overdue' " \
            "WHEN tasks.due_on = ? THEN 'today' ELSE 'later' END",
            Date.current, Date.current
          ])
          Task.visible_to(@viewer).open.group(Arel.sql(bucket)).count
        end
      end

      def events_today
        @events_today ||= Event.visible_to(@viewer)
          .overlapping(Time.current.beginning_of_day..Time.current.end_of_day).count
      end

      # A date is a commitment, so it reads like one: the near ones by name
      # and with their clock time, the far ones by date alone.
      def when_phrase(event)
        date = event.starts_at.to_date
        clock = event.all_day? ? nil : event.starts_at.strftime("%-l:%M %p")

        if date == Date.current
          [ "today", clock ].compact.join(", ")
        elsif date == Date.tomorrow
          [ "tomorrow", clock ].compact.join(", ")
        elsif date.year == Date.current.year
          date.strftime("%b %-d")
        else
          date.strftime("%b %-d, %Y")
        end
      end
  end
end
