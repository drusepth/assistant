import { Controller } from "@hotwired/stimulus"

// Off-canvas sidebar drawer for small screens. The same <aside> is a
// static sidebar at lg+, so open/close only matters below that breakpoint;
// lg: classes override the translate/hidden toggles there.
export default class extends Controller {
  static targets = ["drawer", "backdrop"]

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
}
