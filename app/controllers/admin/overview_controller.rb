module Admin
  class OverviewController < BaseController
    RECENT_ERRORS = 15

    def show
      @errors = AppError.recent.includes(:user).limit(RECENT_ERRORS)
      @error_count = AppError.count
      @queue = QueueStatus.new
      @queue_failures = @queue.recent_failures
      @model_profile = Current.user.household.model_profile

      # Counts, not contents: a household admin may see *that* another member's
      # run failed and why, never the item itself (items stay private until
      # shared — the admin flag is not a master key).
      @failed_tool_runs = ToolRun.failed.count
      @failed_documents = Document.where(analysis_status: :failed).count

      @storage = StorageStatus.new(Current.user.household)

      # Includes each dataset's last failed fetch/import: a background failure
      # nobody would otherwise see belongs on the card it broke, not only in
      # the error log at the bottom of the page.
      @datasets = Datasets::Status.all

      # Counts only, same rule as above: what a reset would take, never what
      # any of it is.
      @reset_preview = HouseholdReset.preview(Current.user.household)
    end
  end
end
