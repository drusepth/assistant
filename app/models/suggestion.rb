# The agent's entire output surface (D20): the agent proposes, the user
# disposes. Watchers write rows here; nothing else in the app is ever
# created, changed, or completed by the agent — accepting a suggestion is
# what materializes anything, and acceptance is always one explicit click.
# Suggestions are personal (no Visible — never shared) and Sectionable, so
# the Dashboard feed and each section's Attend zone are plain queries.
class Suggestion < ApplicationRecord
  include Sectionable

  belongs_to :user

  enum :kind, { nudge: "nudge", heads_up: "heads_up", insight: "insight" }, default: :nudge
  enum :status, { pending: "pending", accepted: "accepted", dismissed: "dismissed", snoozed: "snoozed" },
    default: :pending

  validates :title, :watcher_slug, presence: true
  # The fingerprint (watcher + subject, chosen by the watcher) is what keeps
  # a dismissed nudge from reappearing on every scan.
  validates :fingerprint, presence: true, uniqueness: { scope: :user_id }

  scope :actionable, -> {
    where(status: :pending).or(where(status: :snoozed, snoozed_until: ..Date.current))
  }

  SNOOZE_FOR = 2.weeks

  def snooze!
    update!(status: :snoozed, snoozed_until: SNOOZE_FOR.from_now.to_date)
  end

  def dismiss!
    update!(status: :dismissed)
  end

  # Materializes the action payload as ordinary primitives, tagged with the
  # suggestion's own sections, and returns what it created (nil for payloads
  # the controller handles itself, e.g. a tool redirect).
  def accept!
    created = materialize
    update!(status: :accepted)
    created
  end

  def tool_action = action["tool"]

  # An in-app destination ("look at these photos") — internal paths only,
  # so a payload can never send the user off the instance.
  def path_action
    path = action["path"]
    path if path.is_a?(String) && path.start_with?("/")
  end

  def accept_label
    return "Add task" if action["task"]
    return "Add event" if action["event"]
    return "Open tool" if tool_action
    return "View" if path_action

    "Accept"
  end

  private
    def materialize
      if (attrs = action["task"])
        task = user.tasks.create!(
          title: attrs["title"], notes: attrs["notes"],
          due_on: attrs["due_on"].presence, bucket: :today
        )
        task.sections = sections.to_a
        task
      elsif (attrs = action["event"])
        event = user.events.create!(
          title: attrs["title"], starts_at: attrs["starts_at"], all_day: attrs.fetch("all_day", true)
        )
        event.sections = sections.to_a
        event
      end
    end
end
