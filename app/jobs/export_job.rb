class ExportJob < ApplicationJob
  queue_as :default

  def perform(user)
    archive = Users::Export.new(user).call
    user.export_archive.attach(
      io: archive,
      filename: "assistant-export-#{Date.current.iso8601}.zip",
      content_type: "application/zip"
    )
  end
end
