import { Controller } from "@hotwired/stimulus"

// The chat composer, attached to the form. The draft box grows with its
// content up to a cap; Enter sends and Shift+Enter breaks the line (touch
// keyboards keep Enter as newline and send by button); quick-reply chips
// send a canned turn without eating a typed draft. The textarea itself is
// [data-turbo-permanent] so a half-typed draft survives the page refresh
// that delivers the tutor's reply — which is why a *successful* send has
// to clear it here.
export default class extends Controller {
  static targets = ["input"]
  static values = { maxHeight: { type: Number, default: 240 } }

  connect() {
    this.grow()
    this.inputTarget.focus()
  }

  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
    if (window.matchMedia("(pointer: coarse)").matches) return

    event.preventDefault()
    if (this.inputTarget.value.trim() && !this.sendBlocked) this.send()
  }

  quickReply(event) {
    if (this.sendBlocked) return

    this.stashedDraft = this.inputTarget.value
    this.inputTarget.value = event.params.text
    this.send()
  }

  reset(event) {
    if (!event.detail.success) return

    this.inputTarget.value = this.stashedDraft || ""
    this.stashedDraft = null
    this.grow()
    this.inputTarget.focus()
  }

  grow() {
    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = `${Math.min(input.scrollHeight, this.maxHeightValue)}px`
  }

  send() {
    this.element.requestSubmit()
  }

  get sendBlocked() {
    return this.element.querySelector("[type=submit]")?.disabled
  }
}
