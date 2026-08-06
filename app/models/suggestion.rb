# The agent's only write surface (D20): watchers propose rows here, and
# nothing touches user data until the user accepts — acceptance is always
# one explicit click. Sectionable is what makes the Attend zone and the
# Dashboard feed plain in_section/unscoped queries — the lens model working
# unchanged. Suggestions are personal (a watcher scans your own data), so
# there is no Visible and no sharing.
class Suggestion < ApplicationRecord
  include Sectionable

  belongs_to :user

  enum :kind, { nudge: "nudge", heads_up: "heads_up", insight: "insight" }
  enum :status, { pending: "pending", accepted: "accepted", dismissed: "dismissed", snoozed: "snoozed" }

  validates :title, :watcher_slug, presence: true
  validates :fingerprint, presence: true, uniqueness: { scope: :user_id }

  # What the surfaces show: pending, plus snoozes that have come back around.
  scope :attention, -> { pending.or(snoozed.where(snoozed_until: ..Date.current)) }
  scope :newest_first, -> { order(created_at: :desc) }

  # The action payload is written by a watcher (code, not a model), and
  # still validated here at execution time — accept never runs anything a
  # current watcher couldn't have written.
  ACTION_TYPES = %w[ create_event create_task run_tool ].freeze

  def action_type
    type = action["type"].to_s
    type if ACTION_TYPES.include?(type)
  end

  # For run_tool actions: the registered tool, or nil if it was retired.
  def routed_tool
    Tool.find(action["slug"].to_s) if action_type == "run_tool"
  end

  def accept_label
    case action_type
    when "create_event" then "Add to calendar"
    when "create_task" then "Add task"
    when "run_tool" then "Start"
    else "Got it"
    end
  end

  # Accepting materializes the payload as ordinary owned primitives (or, for
  # run_tool, just marks accepted — the controller sends the user to the
  # prefilled form, and the normal run lifecycle takes it from there).
  def accept!
    case action_type
    when "create_event" then create_action_event
    when "create_task" then create_action_task
    end
    update!(status: :accepted)
  end

  def dismiss! = update!(status: :dismissed)

  def snooze!(until_date = Date.current + 7)
    update!(status: :snoozed, snoozed_until: until_date)
  end

  private
    def create_action_event
      payload = action.fetch("event", {})
      date = parsed_date(payload["date"]) || Date.current
      event = user.events.create!(
        title: payload["title"].presence || title,
        starts_at: date.in_time_zone, all_day: true
      )
      event.sections = sections
    end

    def create_action_task
      payload = action.fetch("task", {})
      due_on = parsed_date(payload["due_on"])
      task = user.tasks.create!(
        title: payload["title"].presence || title, due_on: due_on,
        bucket: due_on && due_on <= Date.current ? :today : :later
      )
      task.sections = sections
    end

    def parsed_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
end
