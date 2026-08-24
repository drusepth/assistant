import { Controller } from "@hotwired/stimulus"

// Holds the chat screen above the on-screen keyboard.
//
// Two platforms, two behaviours. Chrome for Android honours
// `interactive-widget=resizes-content` (see the layout's viewport meta): the
// layout viewport itself shrinks, `100dvh` already excludes the keyboard, and
// there is nothing to do. iOS Safari ignores the hint — the layout viewport
// keeps its full height and only the *visual* viewport shrinks, so a screen
// sized to `100dvh` puts its composer behind the keyboard.
//
// So we measure rather than guess: the gap between the layout viewport and
// what is actually visible is the keyboard, published as --keyboard-inset for
// `.chat-screen` to subtract. On Android that gap is ~0 because innerHeight
// shrank too, which is exactly why the same code is correct on both.
//
// The floor matters. A visualViewport also shrinks when the user pinch-zooms
// or a toolbar slides in, and reacting to those would make the page twitch, so
// anything smaller than a keyboard is treated as no keyboard at all.
const KEYBOARD_FLOOR = 80

export default class extends Controller {
  connect() {
    this.viewport = window.visualViewport
    if (!this.viewport) return

    this.measure = this.measure.bind(this)
    this.viewport.addEventListener("resize", this.measure)
    this.viewport.addEventListener("scroll", this.measure)
    this.measure()
  }

  disconnect() {
    if (!this.viewport) return

    this.viewport.removeEventListener("resize", this.measure)
    this.viewport.removeEventListener("scroll", this.measure)
    document.documentElement.style.removeProperty("--keyboard-inset")
  }

  measure() {
    const hidden = window.innerHeight - this.viewport.height - this.viewport.offsetTop
    const inset = hidden > KEYBOARD_FLOOR ? Math.round(hidden) : 0

    document.documentElement.style.setProperty("--keyboard-inset", `${inset}px`)
  }
}
