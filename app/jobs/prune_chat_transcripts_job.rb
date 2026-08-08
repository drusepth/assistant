# Chat transcripts are working data, not the record (D33, resolving Q13):
# the durable artifact of a session is its explicit-save recap Note. A
# chat run idle past RETENTION is deleted whole — transcript and history
# entry — while its recaps live on as ordinary notes. Weekly via Solid
# Queue recurring; matters most for check-ins, where the transcript is
# the most sensitive text in the app.
class PruneChatTranscriptsJob < ApplicationJob
  queue_as :default

  RETENTION = 90.days

  def perform
    cutoff = RETENTION.ago
    chat_slugs = Tool.all.select { |tool| tool.kind == :chat }.map(&:slug)

    ToolRun.where(tool_slug: chat_slugs).where(created_at: ...cutoff)
      .where.not(id: ToolRunMessage.where(created_at: cutoff..).select(:tool_run_id))
      .find_each(&:destroy!)
  end
end
