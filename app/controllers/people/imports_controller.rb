class People::ImportsController < ApplicationController
  def new
  end

  def create
    import =
      if params[:contacts].present? # picked on-device via the Contact Picker API
        People::Import.new(user: Current.user, file: StringIO.new(params[:contacts]), filename: "device-contacts.json")
      elsif params[:file].present?
        People::Import.new(user: Current.user, file: params[:file])
      end
    return redirect_to new_people_import_path, alert: "Choose a file to import." if import.nil?

    result = import.call

    if result.error
      redirect_to new_people_import_path, alert: result.error
    else
      notice = "Imported #{helpers.pluralize(result.imported, 'contact')}."
      notice += " Skipped #{helpers.pluralize(result.skipped, 'contact')} already in your address book." if result.skipped.positive?
      redirect_to people_path, notice: notice
    end
  end
end
