import { Controller } from "@hotwired/stimulus"

// Pull to refresh (D-reader-density).
//
// "Check now" is the most-wanted action on a feed reader and it was styled
// as the least: an 11px text link in the corner. On a phone the gesture for
// it has been settled for fifteen years, so this is it — pull past the top
// of the river and the sweep starts.
//
// This changes the gesture, not the fetch policy: it presses the page's own
// "Check now" button, so the politeness rules in docs/READER.md — the
// conditional GETs, the per-feed intervals, the backoff — all still decide
// what actually leaves the machine.
//
// The browser has its own pull-to-refresh at scroll zero and it would win,
// reloading the page out from under this one. `overscroll-behavior-y` is
// what turns it off, set on the document while this controller is on the
// page and put back when it leaves, so no other page inherits the change.
const TRIGGER = 72 // px of pull before the sweep fires
const MAX = 96 // px the indicator can travel, so a hard yank doesn't sag
const RESIST = 0.5 // half the finger's travel, so it feels tethered

export default class extends Controller {
  static targets = ["indicator", "form"]

  connect() {
    this.previousOverscroll = document.documentElement.style.overscrollBehaviorY
    document.documentElement.style.overscrollBehaviorY = "contain"

    this.element.addEventListener("touchstart", this.onStart, { passive: true })
    this.element.addEventListener("touchmove", this.onMove, { passive: false })
    this.element.addEventListener("touchend", this.onEnd)
    this.element.addEventListener("touchcancel", this.onEnd)
  }

  disconnect() {
    document.documentElement.style.overscrollBehaviorY = this.previousOverscroll
    this.element.removeEventListener("touchstart", this.onStart)
    this.element.removeEventListener("touchmove", this.onMove)
    this.element.removeEventListener("touchend", this.onEnd)
    this.element.removeEventListener("touchcancel", this.onEnd)
  }

  onStart = (event) => {
    // Only a pull that begins at the very top is a refresh. Anywhere else it
    // is a scroll, and hijacking it would make the list feel sticky.
    this.armed = window.scrollY <= 0 && event.touches.length === 1 && !this.running
    this.startY = event.touches[0]?.clientY ?? 0
    this.pull = 0
  }

  onMove = (event) => {
    if (!this.armed) return

    const delta = event.touches[0].clientY - this.startY
    // An upward move means they meant to scroll after all.
    if (delta <= 0) { this.armed = false; this.reset(); return }

    event.preventDefault()
    this.pull = Math.min(MAX, delta * RESIST)
    this.paint()
  }

  onEnd = () => {
    if (!this.armed) return
    this.armed = false

    if (this.pull >= TRIGGER) this.fire()
    else this.reset()
  }

  paint() {
    if (!this.hasIndicatorTarget) return

    this.indicatorTarget.style.height = `${this.pull}px`
    this.indicatorTarget.style.opacity = Math.min(1, this.pull / TRIGGER)
    this.indicatorTarget.classList.toggle("is-ready", this.pull >= TRIGGER)
  }

  fire() {
    this.running = true
    if (this.hasIndicatorTarget) this.indicatorTarget.classList.add("is-running")
    // The page's own button, so the request, the CSRF token and the redirect
    // are all the ones the link already had.
    this.formTarget?.requestSubmit()
  }

  reset() {
    this.pull = 0
    this.paint()
  }
}
