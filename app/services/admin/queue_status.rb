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
        {
          job_class: execution.job&.class_name || "unknown",
          error: execution.error.to_s.truncate(300),
          failed_at: execution.created_at
        }
      end
    rescue StandardError
      []
    end

    private
      def safe_count(model)
        return nil unless available?

        model.count
      rescue StandardError
        nil
      end
  end
end
