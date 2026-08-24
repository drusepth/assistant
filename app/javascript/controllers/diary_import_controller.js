import { Controller } from "@hotwired/stimulus"

// Drives a staged import to completion, one batch per request.
//
// The batching isn't cosmetic: a decade of someone's journal is thousands of
// seals and thousands of inserts, and the usual way out — a background job —
// is exactly what this container may not use, because key material never
// rides the queue. The cursor lives in the database, so closing this tab
// pauses the import rather than losing it.
export default class extends Controller {
  static targets = ["bar", "status", "done"]
  static values = { url: String }

  connect() {
    this.cancelled = false
    this.step()
  }

  disconnect() {
    this.cancelled = true
  }

  async step() {
    if (this.cancelled) return

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken },
        credentials: "same-origin"
      })

      if (!response.ok) throw new Error(response.status)

      const progress = await response.json()
      this.render(progress)

      if (progress.error) return this.setStatus(progress.error)
      if (progress.done) return this.finish(progress)

      this.step()
    } catch {
      this.setStatus("Import paused — reload this page to pick it up where it stopped.")
    }
  }

  render({ cursor, total, percent }) {
    if (this.hasBarTarget) this.barTarget.style.width = `${percent || 0}%`
    if (total) this.setStatus(`Sealing entry ${cursor} of ${total}…`)
  }

  finish({ imported, skipped }) {
    const skippedNote = skipped ? `, ${skipped} already here` : ""
    this.setStatus(`Done — ${imported} imported${skippedNote}.`)
    if (this.hasBarTarget) this.barTarget.style.width = "100%"
    if (this.hasDoneTarget) this.doneTarget.hidden = false
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
