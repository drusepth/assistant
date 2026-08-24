import { Controller } from "@hotwired/stimulus"

// Saves the entry a few seconds after the writer stops typing, so a diary
// never loses a page to a closed tab. The request is a plain PATCH of the
// form to the entry's own URL — same controller action as the visible Save,
// asking for JSON instead of a redirect — so there is no second write path
// to keep in step with the sealing rules.
export default class extends Controller {
  static targets = ["form", "status"]
  static values = { url: String, delay: { type: Number, default: 4000 } }

  connect() {
    this.timer = null
    this.saving = false
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  queue() {
    if (!this.urlValue) return

    clearTimeout(this.timer)
    this.setStatus("Unsaved")
    this.timer = setTimeout(() => this.save(), this.delayValue)
  }

  async save() {
    if (this.saving || !this.urlValue) return

    this.saving = true
    this.setStatus("Saving…")

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        body: new FormData(this.formTarget),
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })

      if (!response.ok) throw new Error(response.status)

      const { saved_at: savedAt } = await response.json()
      this.setStatus(`Saved ${savedAt}`)
    } catch {
      // Never claim a save that didn't happen — the writer needs to know the
      // words are still only in the textarea.
      this.setStatus("Not saved — keep this tab open")
    } finally {
      this.saving = false
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
