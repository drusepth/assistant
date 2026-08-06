# The instance's error log, surfaced at /admin.
#
# Background work fails out of sight of the person who triggered it, and most
# of it is deliberately swallowed to keep the UI calm — a model that times out
# leaves a task unsorted rather than showing the user a stack trace. That is
# the right product call and the wrong operations call: on a self-hosted box
# nobody finds out the model has been down for a week. Anything swallowed gets
# recorded here instead of vanishing.
#
# Records the shape of a failure (source, class, message, which record), never
# the content of the item that failed — the admin flag is a household role, not
# permission to read another member's private items.
class AppError < ApplicationRecord
  belongs_to :user, optional: true

  # An unattended instance shouldn't grow this table forever, and old errors
  # stop being interesting long before 500 of them accumulate.
  KEPT = 500
  BACKTRACE_LINES = 20
  MESSAGE_LIMIT = 1000

  scope :recent, -> { order(created_at: :desc) }

  # Never raises: logging a failure must not become one. A job that calls this
  # in a rescue block is already having a bad time.
  def self.record(error, source:, user: nil, context: {})
    create!(
      source: source.to_s,
      error_class: error.class.name,
      message: error.message.to_s.truncate(MESSAGE_LIMIT),
      backtrace: error.backtrace&.first(BACKTRACE_LINES)&.join("\n"),
      user: user,
      context: context
    ).tap { prune! }
  rescue StandardError => e
    Rails.logger.error("AppError.record failed: #{e.class}: #{e.message}")
    nil
  end

  def self.prune!
    surplus_ids = recent.offset(KEPT).pluck(:id)
    where(id: surplus_ids).delete_all if surplus_ids.any?
  end

  def backtrace_lines = backtrace.to_s.lines.map(&:chomp)

  # A plain-text account of the failure, built to be pasted whole into a bug
  # report or an AI chat: everything /admin knows about it, nothing that
  # needs the app open to make sense.
  def report
    details = [ created_at.utc.iso8601 ]
    details << "user: #{user.name}" if user
    context.each { |key, value| details << "#{key}: #{value}" }

    [ "#{source} — #{error_class}", details.join(" · "), message, backtrace.presence ]
      .compact.join("\n")
  end

  def self.report_for(errors)
    errors.map(&:report).join("\n\n#{"-" * 40}\n\n")
  end
end
