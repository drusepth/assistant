module Tool
  # The owned-data half of a tool prompt (D19: gather owned context → LLM →
  # draft primitives): everything the invoking user can see in the given
  # sections — and never more, every query walks through visible_to —
  # rendered as compact dated bullet blocks under a character budget.
  # Newest first, whole lines only, each item truncated: a small local
  # model's context window is a scarce resource (the Tier-A constraint).
  class Context
    DEFAULT_BUDGET = 12_000
    ITEM_CHARS = 600
    ITEMS_PER_KIND = 20

    def initialize(user:, section_slugs:, budget: DEFAULT_BUDGET)
      @user = user
      @section_ids = Section.where(slug: section_slugs).ids
      @budget = budget
    end

    def empty? = to_prompt.blank?

    def to_prompt
      @to_prompt ||= render
    end

    private
      def render
        remaining = @budget
        blocks.filter_map do |heading, lines|
          kept = []
          lines.each do |line|
            cost = line.length + 1
            break if cost > remaining

            remaining -= cost
            kept << line
          end
          "#{heading}:\n#{kept.join("\n")}" if kept.any?
        end.join("\n\n")
      end

      def blocks
        [
          [ "Appointments and events", event_lines ],
          [ "Notes", note_lines ],
          [ "Documents", document_lines ],
          [ "Open tasks", task_lines ]
        ]
      end

      def event_lines
        scope(Event).order(starts_at: :desc).limit(ITEMS_PER_KIND).map do |event|
          "- #{event.starts_at.to_date.iso8601} — #{event.title}#{" (upcoming)" if event.starts_at.future?}"
        end
      end

      def note_lines
        scope(Note).order(updated_at: :desc).limit(ITEMS_PER_KIND).map do |note|
          "- #{note.updated_at.to_date.iso8601} — #{[ note.title.presence, note.body.truncate(ITEM_CHARS) ].compact.join(": ")}"
        end
      end

      def document_lines
        scope(Document).order(created_at: :desc).limit(ITEMS_PER_KIND).map do |document|
          gist = document.summary.presence || document.extracted_text.presence
          [ "- #{document.title}", gist&.truncate(ITEM_CHARS) ].compact.join(": ")
        end
      end

      def task_lines
        scope(Task).open.order(:due_on).limit(ITEMS_PER_KIND).map do |task|
          "- #{task.title}#{" (due #{task.due_on.iso8601})" if task.due_on}"
        end
      end

      def scope(klass)
        klass.visible_to(@user).in_section(@section_ids)
      end
  end
end
