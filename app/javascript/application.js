// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import * as ActiveStorage from "@rails/activestorage"
import "controllers"

// Direct uploads (D-storage-seam): forms with direct_upload file fields send bytes
// browser → storage service, so photo batches never funnel through Rails.
ActiveStorage.start()
