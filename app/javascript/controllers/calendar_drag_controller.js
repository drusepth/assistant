import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Drag an event or task onto another day of the calendar to reschedule it.
// Native HTML5 drag and drop, no library: an entry carries what it is and
// the day it sits on, a day carries its date, and a drop posts the move and
// reloads the page in place, where the flash says what moved.
export default class extends Controller {
  static values = { url: String }

  start(event) {
    const entry = event.currentTarget
    this.item = { kind: entry.dataset.kind, id: entry.dataset.id, from: entry.dataset.day }
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", entry.title) // Firefox won't drag without data
    requestAnimationFrame(() => entry.classList.add("opacity-40"))
  }

  over(event) {
    if (!this.item) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    event.currentTarget.dataset.dropActive = ""
  }

  leave(event) {
    const day = event.currentTarget
    if (!day.contains(event.relatedTarget)) delete day.dataset.dropActive
  }

  async drop(event) {
    event.preventDefault()
    const day = event.currentTarget
    delete day.dataset.dropActive
    const item = this.item
    this.item = null
    if (!item || day.dataset.day === item.from) return

    const body = new FormData()
    body.append("kind", item.kind)
    body.append("id", item.id)
    body.append("date", day.dataset.day)
    const token = document.querySelector("meta[name='csrf-token']")?.content

    await fetch(this.urlValue, { method: "POST", body, headers: { "X-CSRF-Token": token }, credentials: "same-origin" })
    Turbo.visit(window.location.href, { action: "replace" })
  }

  end(event) {
    event.currentTarget.classList.remove("opacity-40")
    this.item = null
  }
}
