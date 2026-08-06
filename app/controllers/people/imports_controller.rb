class People::ImportsController < ApplicationController
  def new
  end

  def create
    file = params[:file]
    return redirect_to new_people_import_path, alert: "Choose a file to import." if file.blank?

    result = People::Import.new(user: Current.user, file: file).call

    if result.error
      redirect_to new_people_import_path, alert: result.error
    else
      notice = "Imported #{helpers.pluralize(result.imported, 'contact')}."
      notice += " Skipped #{helpers.pluralize(result.skipped, 'contact')} already in your address book." if result.skipped.positive?
      redirect_to people_path, notice: notice
    end
  end
end
