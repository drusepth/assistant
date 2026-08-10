import { Controller } from "@hotwired/stimulus"

// A small anchored menu: the sidebar's settings menu is the first user.
// Deliberately generic — it knows how to show a panel, close on Escape or
// an outside click, and keep aria-expanded honest. Where the panel sits is
// the markup's business, not this controller's.
export default class extends Controller {
  static targets = ["panel", "trigger"]

  toggle() {
    this.panelTarget.classList.contains("hidden") ? this.open() : this.close()
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.#expanded(true)
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.#expanded(false)
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  #expanded(value) {
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", String(value))
  }
}
