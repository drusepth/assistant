import { Controller } from "@hotwired/stimulus"

// The board's columns as swipe panes on a phone (D-tasks-two-surfaces):
// CSS scroll-snap does all the moving; this only opens on the Today pane
// and keeps the tab highlight in sync with swipes. At lg the track is a
// grid with no overflow, the tabs are hidden, and everything here no-ops.
export default class extends Controller {
  static targets = ["track", "pane", "tab"]
  static values = { initial: { type: Number, default: 1 } }

  connect() {
    this.showPane(this.initialValue, "instant")
    this.sync()
  }

  show(event) {
    this.showPane(Number(event.currentTarget.dataset.index), "smooth")
  }

  showPane(index, behavior) {
    const pane = this.paneTargets[index]
    if (!pane) return
    this.trackTarget.scrollTo({ left: pane.offsetLeft - this.trackTarget.offsetLeft, behavior })
  }

  sync() {
    const current = this.currentIndex()
    this.tabTargets.forEach((tab, index) => tab.classList.toggle("tab-active", index === current))
  }

  // The pane whose left edge sits closest to the track's scroll position —
  // snap-mandatory guarantees it settles on exactly one.
  currentIndex() {
    const left = this.trackTarget.scrollLeft + this.trackTarget.offsetLeft
    let closest = 0
    let closestDistance = Infinity
    this.paneTargets.forEach((pane, index) => {
      const distance = Math.abs(pane.offsetLeft - left)
      if (distance < closestDistance) {
        closestDistance = distance
        closest = index
      }
    })
    return closest
  }
}
