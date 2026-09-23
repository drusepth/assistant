import { Controller } from "@hotwired/stimulus"

// A <details> opened in order to type — a card's "+", the "New group"
// tile — puts the cursor in its first field when it opens, and closes on
// Escape. No-JS it is still an ordinary disclosure.
export default class extends Controller {
  connect() {
    this.onToggle = () => {
      if (this.element.open) this.element.querySelector("input:not([type=hidden]), textarea")?.focus()
    }
    this.element.addEventListener("toggle", this.onToggle)
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.onToggle)
  }

  close(event) {
    if (!this.element.open || event.defaultPrevented) return
    this.element.open = false
    this.element.querySelector("summary")?.focus()
  }
}
