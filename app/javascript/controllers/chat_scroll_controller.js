import { Controller } from "@hotwired/stimulus"

// Keeps the transcript pinned to the newest turn without reversing the DOM.
// The old surface used flex-col-reverse, which pins for free but hands
// screen readers, text selection, and copy-paste the conversation backwards.
// Natural order plus a little scroll management is what chat UIs actually
// do: land at the bottom, follow new turns while the user is reading the
// bottom, and stop following — offering a way back — the moment they scroll
// up into history.
export default class extends Controller {
  static targets = ["scroller", "jump"]
  static values = { threshold: { type: Number, default: 64 } }

  connect() {
    this.pinned = true
    requestAnimationFrame(() => this.scrollToBottom("auto"))

    this.observer = new MutationObserver(() => this.follow())
    this.observer.observe(this.scrollerTarget, { childList: true, subtree: true, characterData: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  track() {
    this.pinned = this.distanceFromBottom <= this.thresholdValue
    this.refreshJump()
  }

  jump() {
    this.pinned = true
    this.scrollToBottom("smooth")
    this.refreshJump()
  }

  follow() {
    if (this.pinned) this.scrollToBottom("smooth")
    this.refreshJump()
  }

  scrollToBottom(behavior) {
    this.scrollerTarget.scrollTo({ top: this.scrollerTarget.scrollHeight, behavior })
  }

  // Nothing to jump back to until there's history above the fold.
  refreshJump() {
    if (!this.hasJumpTarget) return

    this.jumpTarget.classList.toggle("hidden", this.pinned || !this.scrollable)
  }

  get distanceFromBottom() {
    const scroller = this.scrollerTarget
    return scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight
  }

  get scrollable() {
    return this.scrollerTarget.scrollHeight > this.scrollerTarget.clientHeight
  }
}
