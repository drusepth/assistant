# One turn of a chat-kind tool run (D29). user/assistant turns are the
# conversation the model sees; a notice is the app speaking (a failed turn's
# retry hint) — rendered in the transcript, never sent to the model.
class ToolRunMessage < ApplicationRecord
  belongs_to :tool_run

  enum :role, { user: "user", assistant: "assistant", notice: "notice" }, suffix: true

  validates :content, presence: true

  scope :ordered, -> { order(:created_at, :id) }
  scope :conversational, -> { where(role: %i[ user assistant ]) }
end
