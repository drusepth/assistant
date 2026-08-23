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

    // A morphing page refresh (a sent message, an arriving reply) leaves this
    // element in place, so connect() won't run again — the observer is what
    // notices the new turn and follows it down.
    this.observer = new MutationObserver(() => this.follow())
    this.observer.observe(this.scrollerTarget, { childList: true, subtree: true, characterData: true })
  }

  disconnect() {
    this.observer?.disconnect()
    clearTimeout(this.autoScrollTimer)
  }

  track() {
    // A smooth scroll of our own fires scroll events the whole way down,
    // every one of them "far from the bottom" — reading those as the user
    // leaving would unpin the transcript mid-follow.
    if (this.autoScrolling) return

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
    clearTimeout(this.autoScrollTimer)
    this.autoScrolling = true
    this.autoScrollTimer = setTimeout(() => { this.autoScrolling = false }, 500)

    // A behavior passed to scrollTo() overrides the CSS scroll-behavior, so
    // the app-wide reduced-motion rule can't reach this call — the transcript
    // would still glide on every turn for someone who asked it not to.
    this.scrollerTarget.scrollTo({ top: this.scrollerTarget.scrollHeight, behavior: this.reducedMotion ? "auto" : behavior })
  }

  get reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
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
