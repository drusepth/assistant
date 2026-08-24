import { Controller } from "@hotwired/stimulus"

// The sidebar has two independent behaviours that live on the same <aside>.
//
// Below lg it is an off-canvas drawer: open/close slide it in and out, and
// the lg: classes in the markup override the translate there.
//
// At lg+ it is a static rail that can collapse to icons only (the design's
// chevron toggle). Collapsing is a desktop-only idea — a drawer you opened
// deliberately should never show up as a strip of unlabelled icons — so the
// collapsed class is namespaced `lg:` and the toggle button is hidden below
// lg. The choice persists in localStorage because a rail that forgets it on
// every page load is worse than one that never collapsed.
const STORAGE_KEY = "nav:collapsed"

// Drag thresholds for the drawer's touch gestures.
//
// EDGE is how far in from the left the gesture may start. Both mobile
// browsers reserve the outermost ~24px for their own back gesture and never
// forward those touches to the page at all, so the band has to reach past
// that to leave any of itself usable — which is also why the swipe can only
// ever be a shortcut and never the way in (see the buttons in the layout).
// Installed to the home screen there is no back gesture and the whole band
// works.
const EDGE = 48
// How far the finger must travel to count as a swipe rather than a tap that
// wandered, and how much more horizontal than vertical it must be before we
// treat it as a drawer gesture instead of a scroll.
const DISTANCE = 56
const SLOPE = 1.5
const DEADZONE = 10
// The drawer only exists below lg (Tailwind's 64rem); above it the rail is
// static furniture and a swipe at it means nothing.
const RAIL = "(min-width: 64rem)"

export default class extends Controller {
  static targets = ["drawer", "backdrop", "collapsible"]
  static classes = ["collapsed"]

  // The gesture in progress, or null when there isn't one worth watching.
  #swipe = null

  connect() {
    // Restore before first paint where possible; a morph re-runs this too,
    // which is what keeps the rail from expanding under a Turbo refresh.
    this.#apply(this.#stored)
  }

  open() {
    this.drawerTarget.classList.remove("-translate-x-full")
    this.backdropTarget.classList.remove("hidden")
  }

  close() {
    this.drawerTarget.classList.add("-translate-x-full")
    this.backdropTarget.classList.add("hidden")
  }

  toggle() {
    if (this.#isOpen) {
      this.close()
    } else {
      this.open()
    }
  }

  // Touch: drag right from the left edge to open, drag the open drawer left
  // to close. Threshold-based rather than finger-following — the drawer's
  // own transition does the animating, and a gesture that only has to be
  // recognised can't get stuck half-open when a touch is cancelled.
  //
  // Stimulus registers touchstart/touchmove as passive listeners, and
  // nothing here calls preventDefault, so the page never loses a frame of
  // scrolling to this.
  swipeStart(event) {
    this.#swipe = null
    if (event.touches.length !== 1) return
    if (window.matchMedia(RAIL).matches) return

    const touch = event.touches[0]
    const open = this.#isOpen
    // Opening starts in the edge band on a closed drawer; closing starts
    // anywhere on the open one. A touch on the backdrop is a tap to close
    // already, so it isn't a gesture we need to claim.
    if (open && !this.drawerTarget.contains(event.target)) return
    if (!open && touch.clientX > EDGE) return
    // A carousel, a wide table, a code block: whatever the finger is on top
    // of gets the horizontal drag it was already going to get.
    if (this.#scrollsHorizontally(event.target)) return

    this.#swipe = { x: touch.clientX, y: touch.clientY, dx: 0, dy: 0, open }
  }

  swipeMove(event) {
    if (!this.#swipe || event.touches.length !== 1) return

    const touch = event.touches[0]
    this.#swipe.dx = touch.clientX - this.#swipe.x
    this.#swipe.dy = touch.clientY - this.#swipe.y

    // Judge the direction only once the finger has actually gone somewhere:
    // the first pixel of any drag is noise, and at dx = 0 every gesture
    // looks vertical.
    if (Math.hypot(this.#swipe.dx, this.#swipe.dy) < DEADZONE) return

    // Committed to a scroll: stop watching rather than second-guessing it
    // when the finger curves back.
    if (Math.abs(this.#swipe.dy) > Math.abs(this.#swipe.dx) * SLOPE) this.#swipe = null
  }

  swipeEnd() {
    const swipe = this.#swipe
    this.#swipe = null
    if (!swipe) return
    if (Math.abs(swipe.dx) < DISTANCE) return
    if (Math.abs(swipe.dx) < Math.abs(swipe.dy) * SLOPE) return

    if (swipe.open && swipe.dx < 0) this.close()
    if (!swipe.open && swipe.dx > 0) this.open()
  }

  // The chevron: collapse the desktop rail to icons, or expand it back.
  toggleCollapsed() {
    const next = !this.#stored
    try {
      localStorage.setItem(STORAGE_KEY, next ? "1" : "0")
    } catch {
      // Private mode or a blocked store — the rail still toggles for this
      // page, it just won't be remembered.
    }
    this.#apply(next)
  }

  get #isOpen() {
    return !this.drawerTarget.classList.contains("-translate-x-full")
  }

  #scrollsHorizontally(node) {
    for (let el = node; el instanceof Element && el !== this.element; el = el.parentElement) {
      if (el.scrollWidth <= el.clientWidth) continue
      if (/auto|scroll/.test(getComputedStyle(el).overflowX)) return true
    }
    return false
  }

  get #stored() {
    try {
      return localStorage.getItem(STORAGE_KEY) === "1"
    } catch {
      return false
    }
  }

  #apply(collapsed) {
    this.collapsibleTargets.forEach((el) => {
      el.classList.toggle(this.collapsedClass, collapsed)
    })
    if (this.hasDrawerTarget) {
      this.drawerTarget.dataset.navCollapsed = collapsed ? "true" : "false"
    }
  }
}
