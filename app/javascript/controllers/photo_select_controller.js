import { Controller } from "@hotwired/stimulus"

// Multi-select over the photo grid: toggle selection mode, tap tiles to
// pick them, then act on the batch from the bottom bar (add to an album,
// or remove from the one being viewed). While selecting, tiles stop being
// links and the lightbox stays shut.
export default class extends Controller {
  static targets = ["tile", "bar", "count", "ids", "toggle", "albumSelect"]

  connect() {
    this.selected = new Set()
  }

  toggleMode() {
    this.selecting = !this.selecting
    this.element.dataset.selecting = this.selecting ? "true" : ""
    if (this.hasToggleTarget) this.toggleTarget.textContent = this.selecting ? "Cancel" : "Select"
    if (!this.selecting) this.clearSelection()
    this.refresh()
  }

  toggleTile(event) {
    if (!this.selecting) return

    event.preventDefault()
    event.stopImmediatePropagation()

    const tile = event.currentTarget
    const id = tile.dataset.photoId
    if (this.selected.has(id)) {
      this.selected.delete(id)
      tile.classList.remove("ring-4", "ring-inset", "ring-primary-500")
    } else {
      this.selected.add(id)
      tile.classList.add("ring-4", "ring-inset", "ring-primary-500")
    }
    this.refresh()
  }

  // The add-to-album form posts to the album chosen in its select; each
  // option carries its own URL so the path never lives in JS.
  prepare(event) {
    const option = this.albumSelectTarget.selectedOptions[0]
    if (this.selected.size === 0 || !option || !option.dataset.url) {
      event.preventDefault()
      return
    }
    event.target.action = option.dataset.url
  }

  refresh() {
    if (this.hasCountTarget) {
      this.countTarget.textContent = `${this.selected.size} selected`
    }
    if (this.hasBarTarget) {
      this.barTarget.classList.toggle("hidden", !this.selecting || this.selected.size === 0)
    }
    const inputs = Array.from(this.selected)
      .map((id) => `<input type="hidden" name="photo_ids[]" value="${id}">`)
      .join("")
    this.idsTargets.forEach((container) => (container.innerHTML = inputs))
  }

  clearSelection() {
    this.selected.clear()
    this.tileTargets.forEach((tile) => tile.classList.remove("ring-4", "ring-inset", "ring-primary-500"))
  }
}
