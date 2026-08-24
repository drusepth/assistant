import { Controller } from "@hotwired/stimulus"

// Saves the entry a few seconds after the writer stops typing, so a diary
// never loses a page to a closed tab or a dead battery.
//
// It covers a brand-new entry as well as an existing one, which is the whole
// point: the longest anyone writes without saving is their first sitting.
// The first save POSTs and creates; from then on the controller — and the
// form around it — re-point at the entry that came back, so the visible
// Save button can't create a second copy.
//
// Both paths hit the same controller actions as the visible button, asking
// for JSON instead of a redirect, so there is no second write path to keep
// in step with the sealing rules.
export default class extends Controller {
  static targets = ["form", "status", "body", "lock", "submit"]
  static values = {
    url: String,
    createUrl: String,
    delay: { type: Number, default: 4000 }
  }

  connect() {
    this.timer = null
    this.saving = false
    this.stale = false
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  queue() {
    // A stale form has lost the race to another tab; further saves would
    // overwrite whatever that tab wrote. Stop offering to.
    if (this.stale) return
    if (!this.urlValue && !this.createUrlValue) return

    clearTimeout(this.timer)
    this.setStatus("Unsaved")
    this.timer = setTimeout(() => this.save(), this.delayValue)
  }

  async save() {
    if (this.saving || this.stale) return
    // Nothing to create yet: an empty new entry is not a draft, it's a blank
    // page, and the server would rightly refuse it.
    if (!this.urlValue && !this.hasContent) return

    this.saving = true
    this.setStatus("Saving…")

    const creating = !this.urlValue
    try {
      const response = await fetch(creating ? this.createUrlValue : this.urlValue, {
        method: creating ? "POST" : "PATCH",
        body: new FormData(this.formTarget),
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })

      if (response.status === 409) return this.markStale(await response.json())
      if (!response.ok) throw new Error(response.status)

      const data = await response.json()
      if (creating) this.adoptCreatedEntry(data)
      if (data.lock_version !== undefined && this.hasLockTarget) {
        this.lockTarget.value = data.lock_version
      }
      this.setStatus(`Saved ${data.saved_at}`)
    } catch {
      // Never claim a save that didn't happen — the writer needs to know the
      // words are still only in the textarea.
      this.setStatus("Not saved — keep this tab open")
    } finally {
      this.saving = false
    }
  }

  // After the first save the page is editing an entry, not creating one:
  // the form, the address bar, and the button all have to agree, or the
  // visible Save would POST a duplicate.
  adoptCreatedEntry({ url, lock_version: lockVersion }) {
    this.urlValue = url
    this.createUrlValue = ""
    this.formTarget.action = url
    this.addHidden("_method", "patch")
    this.addHidden("diary_entry[lock_version]", lockVersion, "lock")
    if (this.hasSubmitTarget) this.submitTarget.value = "Done"
    history.replaceState({}, "", `${url}/edit`)
  }

  markStale({ message }) {
    this.stale = true
    this.setStatus(message || "Opened in another tab — reload before editing here")
  }

  addHidden(name, value, target) {
    let field = this.formTarget.querySelector(`input[name="${name}"]`)
    if (!field) {
      field = document.createElement("input")
      field.type = "hidden"
      field.name = name
      if (target) field.setAttribute(`data-${this.identifier}-target`, target)
      this.formTarget.appendChild(field)
    }
    field.value = value
  }

  get hasContent() {
    return this.hasBodyTarget && this.bodyTarget.value.trim().length > 0
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
