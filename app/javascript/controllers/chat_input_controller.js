import { Controller } from "@hotwired/stimulus"

// The chat composer, attached to the form. The draft box grows with its
// content up to a cap; Enter sends and Shift+Enter breaks the line (touch
// keyboards keep Enter as newline and send by button, so Cmd/Ctrl+Enter is
// there for hardware keyboards on tablets); quick-reply chips send a canned
// turn without eating a typed draft. The textarea itself is
// [data-turbo-permanent] so a half-typed draft survives the page refresh
// that delivers the tutor's reply — which is why a *successful* send has
// to clear it here.
//
// The send button is dimmed on an empty draft, but only ever on top of the
// server's own [data-locked] (a reply is in flight): the markup ships
// enabled, so a composer with no JS still sends.
export default class extends Controller {
  static targets = ["input", "send"]
  static values = { maxHeight: { type: Number, default: 240 } }

  connect() {
    this.grow()
    this.refreshSend()
    if (!this.touch) this.inputTarget.focus()
  }

  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    const shortcut = event.metaKey || event.ctrlKey
    if (this.touch && !shortcut) return

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
    this.refreshSend()
    if (!this.touch) this.inputTarget.focus()
  }

  grow() {
    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = `${Math.min(input.scrollHeight, this.maxHeightValue)}px`
    this.refreshSend()
  }

  send() {
    this.element.requestSubmit()
  }

  refreshSend() {
    if (!this.hasSendTarget || this.sendBlocked) return

    this.sendTarget.disabled = this.inputTarget.value.trim() === ""
  }

  get sendBlocked() {
    return this.hasSendTarget && this.sendTarget.hasAttribute("data-locked")
  }

  get touch() {
    return window.matchMedia("(pointer: coarse)").matches
  }
}
