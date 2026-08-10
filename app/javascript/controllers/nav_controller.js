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

export default class extends Controller {
  static targets = ["drawer", "backdrop", "collapsible"]
  static classes = ["collapsed"]

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
    if (this.drawerTarget.classList.contains("-translate-x-full")) {
      this.open()
    } else {
      this.close()
    }
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
