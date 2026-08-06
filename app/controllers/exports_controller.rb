class ExportsController < ApplicationController
  def create
    ExportJob.perform_later(Current.user)
    redirect_to settings_path, notice: "Building your export — refresh Settings in a moment to download it."
  end
end
