import { Controller } from "@hotwired/stimulus"

// The chat composer textarea: grows with the draft up to a cap, and keeps
// the chat rhythm — Enter sends, Shift+Enter starts a new line.
export default class extends Controller {
  static values = { maxHeight: { type: Number, default: 240 } }

  connect() {
    this.grow()
  }

  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    if (this.element.value.trim()) this.element.form.requestSubmit()
  }

  grow() {
    this.element.style.height = "auto"
    this.element.style.height = `${Math.min(this.element.scrollHeight, this.maxHeightValue)}px`
  }
}
