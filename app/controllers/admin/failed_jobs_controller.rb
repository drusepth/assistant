module Admin
  # Remedies for the failed-jobs panel: a failed execution otherwise sits in
  # the count forever. Everything goes through QueueStatus, which shrugs off
  # a missing queue database instead of crashing.
  class FailedJobsController < BaseController
    def retry
      notice = queue.retry_failure(params[:id]) ?
        "Job queued to run again." : "That failed job is no longer there."
      redirect_to admin_root_path, notice: notice
    end

    def discard
      notice = queue.discard_failure(params[:id]) ?
        "Failed job discarded." : "That failed job is no longer there."
      redirect_to admin_root_path, notice: notice
    end

    def discard_all
      notice = queue.discard_all_failures ?
        "All failed jobs discarded." : "The job backend isn't available."
      redirect_to admin_root_path, notice: notice
    end

    private
      def queue = QueueStatus.new
  end
end
