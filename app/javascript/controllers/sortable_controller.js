import { Controller } from "@hotwired/stimulus"

// Native HTML5 drag-to-reorder for a vertical list — no library. Rows move
// live while dragging; each row carries a hidden input that submits in DOM
// order, so dropping a row is all the persistence needs.
export default class extends Controller {
  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", "") // Firefox won't drag without data
    requestAnimationFrame(() => this.dragged.classList.add("opacity-40"))
  }

  dragOver(event) {
    event.preventDefault()
    const row = event.currentTarget
    if (!this.dragged || row === this.dragged) return

    const rect = row.getBoundingClientRect()
    const before = event.clientY < rect.top + rect.height / 2
    row.parentNode.insertBefore(this.dragged, before ? row : row.nextSibling)
  }

  drop(event) {
    event.preventDefault()
  }

  dragEnd() {
    this.dragged?.classList.remove("opacity-40")
    this.dragged = null
  }
}
