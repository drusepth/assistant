import { Controller } from "@hotwired/stimulus"

// A sheet up from the bottom of a phone — the river's scope picker, and
// anything else that is a list of choices rather than a confirmation.
//
// Bottom rather than top because that is where the thumb is: the thing this
// replaced was two rows of links pinned above four hundred headlines, at the
// far end of the reach of the hand holding the device.
//
// It closes on the backdrop, on Escape, and on choosing something — the last
// one for free, because every choice inside is an ordinary link and the page
// it navigates to renders a closed sheet.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.onKey = (event) => { if (event.key === "Escape") this.close() }
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    this.unlock()
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    // The page behind must not scroll while a sheet is over it; without this
    // a flick meant for the sheet's own list drags the river instead.
    this.scrollY = window.scrollY
    document.body.style.position = "fixed"
    document.body.style.top = `-${this.scrollY}px`
    document.body.style.width = "100%"
    this.panelTarget.querySelector("a, button")?.focus()
  }

  close() {
    if (this.panelTarget.classList.contains("hidden")) return
    this.panelTarget.classList.add("hidden")
    this.unlock()
  }

  // Only a press on the backdrop itself, never one that bubbled up out of
  // the sheet's own content.
  backdrop(event) {
    if (event.target === this.panelTarget) this.close()
  }

  unlock() {
    if (document.body.style.position !== "fixed") return

    document.body.style.position = ""
    document.body.style.top = ""
    document.body.style.width = ""
    window.scrollTo(0, this.scrollY || 0)
  }
}
