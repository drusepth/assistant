# One turn of a chat-kind tool run (D29). user/assistant turns are the
# conversation the model sees; a notice is the app speaking (a failed turn's
# retry hint) — rendered in the transcript, never sent to the model.
class ToolRunMessage < ApplicationRecord
  belongs_to :tool_run

  enum :role, { user: "user", assistant: "assistant", notice: "notice" }, suffix: true

  validates :content, presence: true

  # How many turns the transcript renders at once. A long tutor session is
  # hundreds of bubbles, and rendering them all put the whole history in the
  # DOM of a phone that may be five years old — so the surface opens on the
  # newest PAGE and fetches backwards from there.
  PAGE = 40

  scope :ordered, -> { order(:created_at, :id) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :conversational, -> { where(role: %i[ user assistant ]) }

  # Everything that sorts before this message under `ordered`. The cursor is
  # the (created_at, id) pair rather than the id alone, so paging back agrees
  # exactly with the order the transcript renders in — an id cursor would
  # disagree the moment two rows share a timestamp out of id order.
  scope :before, ->(message) {
    where("(tool_run_messages.created_at, tool_run_messages.id) < (?, ?)", message.created_at, message.id)
  }

  # The newest `limit` turns, oldest-first for rendering, plus whether there
  # is anything older — one query answering both, by asking for one more row
  # than we mean to show.
  def self.window(limit: PAGE, before: nil)
    scope = newest_first.limit(limit + 1)
    scope = scope.before(before) if before
    rows = scope.to_a

    [ rows.first(limit).reverse, rows.length > limit ]
  end
end
