# A safe read of the job backend for /admin.
#
# Solid Queue is configured in production only (config/environments/production.rb)
# and lives in a separate `queue` database, so in development and test the tables
# genuinely are not there. Every reader here has to survive that rather than
# 500 the admin page on a developer's laptop — hence `available?` and the blanket
# rescues: this is a status panel, and a status panel that crashes is worse than
# one that says "not available".
module Admin
  class QueueStatus
    def adapter_name
      ActiveJob::Base.queue_adapter.class.name.demodulize.sub(/Adapter\z/, "")
    rescue StandardError
      "unknown"
    end

    def available?
      return false unless defined?(SolidQueue::FailedExecution)

      SolidQueue::FailedExecution.table_exists?
    rescue StandardError
      false
    end

    def failed_count = safe_count(SolidQueue::FailedExecution)
    def pending_count = safe_count(SolidQueue::ReadyExecution)
    def scheduled_count = safe_count(SolidQueue::ScheduledExecution)

    # The most recent failures, flattened into plain hashes so the view never
    # touches a Solid Queue model that may not exist.
    def recent_failures(limit: 10)
      return [] unless available?

      SolidQueue::FailedExecution.includes(:job).order(created_at: :desc).limit(limit).map do |execution|
        error = (execution.error || {}).with_indifferent_access
        {
          id: execution.id,
          job_class: execution.job&.class_name || "unknown",
          error_class: error[:exception_class].to_s.presence || "unknown",
          message: error[:message].to_s,
          backtrace: Array(error[:backtrace]).first(AppError::BACKTRACE_LINES).join("\n"),
          failed_at: execution.created_at
        }
      end
    rescue StandardError
      []
    end

    # Same paste-ready shape as AppError#report, for failures that never made
    # it into the error log because they died before or outside a job's own
    # error handling.
    def failure_report(failure)
      [ "#{failure[:job_class]} — #{failure[:error_class]}",
        failure[:failed_at]&.utc&.iso8601,
        failure[:message].presence,
        failure[:backtrace].presence ].compact.join("\n")
    end

    def report_for(failures)
      failures.map { |failure| failure_report(failure) }.join("\n\n#{"-" * 40}\n\n")
    end

    # Re-dispatches the failed job; true when there was one to retry. A job
    # whose class was renamed retries clean once a deploy brings the new name
    # (or an alias for the old one).
    def retry_failure(id)
      with_failure(id) { |failure| failure.retry }
    end

    # Drops the execution and its job — the remedy for a failure that will
    # never succeed (e.g. a class that no longer exists and shouldn't run).
    def discard_failure(id)
      with_failure(id) { |failure| failure.discard }
    end

    def discard_all_failures
      return false unless available?

      SolidQueue::FailedExecution.discard_all_in_batches
      true
    rescue StandardError
      false
    end

    private
      def with_failure(id)
        return false unless available?

        failure = SolidQueue::FailedExecution.find_by(id: id)
        return false unless failure

        yield failure
        true
      rescue StandardError
        false
      end

      def safe_count(model)
        return nil unless available?

        model.count
      rescue StandardError
        nil
      end
  end
end
