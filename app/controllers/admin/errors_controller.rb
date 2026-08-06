module Admin
  class ErrorsController < BaseController
    PER_PAGE = 100

    def index
      @errors = AppError.recent.includes(:user).limit(PER_PAGE)
      @error_count = AppError.count
      @report = AppError.report_for(@errors)
    end

    def destroy_all
      AppError.delete_all
      redirect_to admin_errors_path, notice: "Error log cleared."
    end
  end
end
