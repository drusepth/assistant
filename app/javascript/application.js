// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import * as ActiveStorage from "@rails/activestorage"
import "controllers"

// Direct uploads (D-storage-seam): forms with direct_upload file fields send bytes
// browser → storage service, so photo batches never funnel through Rails.
ActiveStorage.start()

// The service worker, registered on every authenticated page rather than only
// when somebody turns on push in Settings (D22) — a browser will not offer to
// install an app whose worker it has never seen, and almost nobody had ever
// clicked that button. Registering is idempotent, so the push flow can still
// call it and get the same registration back.
//
// It only handles push today. It has no `fetch` handler, which means Chrome
// will not raise its install prompt yet; adding one routes every request in
// the app through the worker, and that is a decision about offline behaviour
// rather than a detail of installing (see CHAT_PLAN.md W5).
//
// Scoped for free: layouts/public.html.erb ships no JavaScript at all, so a
// share-link visitor never registers anything.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service_worker.js").catch(() => {
      // A worker that won't register costs the install prompt and nothing else.
    })
  })
}
