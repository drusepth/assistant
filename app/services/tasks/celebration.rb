module Tasks
  # The dopamine hit for finishing a task (D-task-celebration). Completion
  # redirects (button_to → PATCH → redirect_back), so the party can't run at
  # click time — it's decided here, stashed in the flash, and fired by the
  # `celebration` Stimulus controller on the page that comes back.
  #
  # The tier escalates so the big moments still feel big: an ordinary task is
  # a confetti burst, the last goal step is a bigger one, and clearing the
  # board is the full fireworks. Nothing here costs a model call — it's all
  # counting rows the user already has.
  class Celebration
    # How many finishes in a day before the copy starts noticing.
    STREAK_COPY = {
      3 => "Three down today 🔥",
      5 => "Five today. Machine.",
      8 => "Eight?! Save some for tomorrow."
    }.freeze

    CHEERS = [
      "Done!", "Nailed it!", "Boom.", "One less thing.", "Crushed it.",
      "That's the one.", "Off your plate.", "Yes!"
    ].freeze

    def self.for(task) = new(task).payload

    def initialize(task)
      @task = task
      @user = task.user
    end

    # nil when there's nothing to celebrate — the user turned celebrations
    # off, or the task came back out of Done.
    def payload
      return nil unless @user.celebrations? && @task.completed?

      { tier: tier, headline: headline, note: note, token: SecureRandom.hex(4) }
    end

    private
      # Biggest true thing wins: an empty board beats a finished goal beats a
      # streak beats an ordinary win.
      def tier
        return "board" if board_clear?
        return "goal" if goal_finished?
        return "streak" if streak_copy
        "task"
      end

      def headline
        case tier
        when "board" then "Today's clear!"
        when "goal" then "Goal complete!"
        when "streak" then streak_copy
        else CHEERS[@task.id.to_i % CHEERS.size]
        end
      end

      def note
        case tier
        when "board" then "Nothing left on today's plate. Go enjoy it."
        when "goal" then @task.goal.title
        else @task.title
        end
      end

      def goal_finished? = @task.goal&.done?

      # Nothing open that today would put in front of the user — the Today
      # column's own rule (bucket ∪ arrived due date), asked of the database.
      def board_clear?
        @user.tasks.open.where("bucket = ? OR due_on <= ?", Task.buckets[:today], Date.current).none?
      end

      def streak_copy
        return @streak_copy if defined?(@streak_copy)
        @streak_copy = STREAK_COPY[finished_today]
      end

      def finished_today
        @finished_today ||= @user.tasks.completed.where(completed_at: Time.current.all_day).count
      end
  end
end
