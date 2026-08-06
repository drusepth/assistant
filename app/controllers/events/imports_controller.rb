class Events::ImportsController < ApplicationController
  def new
  end

  def create
    file = params[:file]
    return redirect_to new_events_import_path, alert: "Choose a file to import." if file.blank?

    result = Events::Import.new(user: Current.user, file: file).call

    if result.error
      redirect_to new_events_import_path, alert: result.error
    else
      notice = "Imported #{helpers.pluralize(result.imported, 'event')}."
      notice += " Skipped #{helpers.pluralize(result.skipped, 'event')} already on your calendar." if result.skipped.positive?
      redirect_to calendar_path, notice: notice
    end
  end
end
