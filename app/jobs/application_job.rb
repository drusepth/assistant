class ApplicationJob < ActiveJob::Base
  # A record deleted between enqueue and perform is routine, not a failure —
  # the work the job carried died with the record. Without this, every
  # "categorize a task the user already deleted" lands in the failed-jobs
  # table looking like something broke.
  discard_on ActiveJob::DeserializationError

  # The D23 safety net: an error nobody rescued still gets written to the
  # /admin error log — with its backtrace — before it goes to the job
  # backend, where on a self-hosted box nobody is looking.
  around_perform :record_unhandled_errors

  # Background work computes dates too — the weekly scan, the watchers, the
  # renewal radar. Without this they'd disagree with the pages that show
  # their output (D-household-profile).
  around_perform :use_household_time_zone

  private
    def use_household_time_zone(&block)
      zone = job_user&.household&.zone
      zone ? Time.use_zone(zone, &block) : block.call
    end

    def record_unhandled_errors
      yield
    rescue StandardError => e
      record_failure(e, user: job_user) unless recorded?(e) || will_retry?(e)
      raise
    end

    # Overridden by RetriesModelCalls. Anything else never retries, so every
    # escaping error is final and worth writing down.
    def will_retry?(_error) = false

    def record_failure(error, user: nil, context: {})
      (@recorded_errors ||= []) << error
      AppError.record(error, source: self.class.name, user: user, context: context)
    end

    def recorded?(error) = @recorded_errors&.include?(error)

    # Best-effort attribution: jobs take either the user or one of the
    # user's records as an argument. Used for error attribution and for the
    # time zone the job should compute in.
    def job_user
      arguments.each do |argument|
        return argument if argument.is_a?(User)

        owner = argument.user if argument.respond_to?(:user)
        return owner if owner.is_a?(User)
      end
      nil
    rescue StandardError
      # Attribution must never turn one failure into two.
      nil
    end
end
