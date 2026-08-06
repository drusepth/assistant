module Admin
  class OverviewController < BaseController
    RECENT_ERRORS = 15

    def show
      @errors = AppError.recent.includes(:user).limit(RECENT_ERRORS)
      @error_count = AppError.count
      @queue = QueueStatus.new
      @model_profile = Current.user.household.model_profile

      # Counts, not contents: a household admin may see *that* another member's
      # run failed and why, never the item itself (items stay private until
      # shared — the admin flag is not a master key).
      @failed_tool_runs = ToolRun.failed.count
      @failed_documents = Document.where(analysis_status: :failed).count
    end
  end
end
