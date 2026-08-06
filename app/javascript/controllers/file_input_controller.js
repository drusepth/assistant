import { Controller } from "@hotwired/stimulus"

// Handles styled file input dropzones: previewing chosen file name/size and drag-and-drop feedback.
export default class extends Controller {
  static targets = ["input", "idle", "selected", "filename", "filesize"]

  connect() {
    this.updateState()
  }

  updateState() {
    const file = this.inputTarget.files && this.inputTarget.files[0]
    if (file) {
      if (this.hasFilenameTarget) {
        this.filenameTarget.textContent = file.name
      }
      if (this.hasFilesizeTarget) {
        this.filesizeTarget.textContent = `(${this.formatBytes(file.size)})`
      }
      if (this.hasIdleTarget) this.idleTarget.classList.add("hidden")
      if (this.hasSelectedTarget) {
        this.selectedTarget.classList.remove("hidden")
        this.selectedTarget.classList.add("flex")
      }
    } else {
      if (this.hasIdleTarget) this.idleTarget.classList.remove("hidden")
      if (this.hasSelectedTarget) {
        this.selectedTarget.classList.add("hidden")
        this.selectedTarget.classList.remove("flex")
      }
    }
  }

  dragOver(event) {
    event.preventDefault()
    this.element.classList.add("border-primary-500", "bg-primary-100/50", "scale-[1.01]")
  }

  dragLeave(event) {
    event.preventDefault()
    this.element.classList.remove("border-primary-500", "bg-primary-100/50", "scale-[1.01]")
  }

  drop(event) {
    event.preventDefault()
    this.element.classList.remove("border-primary-500", "bg-primary-100/50", "scale-[1.01]")
    if (event.dataTransfer.files && event.dataTransfer.files.length > 0) {
      this.inputTarget.files = event.dataTransfer.files
      this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
      this.updateState()
    }
  }

  formatBytes(bytes) {
    if (bytes === 0) return "0 B"
    const k = 1024
    const sizes = ["B", "KB", "MB", "GB"]
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i]
  }
}
