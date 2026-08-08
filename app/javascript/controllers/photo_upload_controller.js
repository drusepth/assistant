import { Controller } from "@hotwired/stimulus"

// Batch photo capture: click or drop files anywhere on the page, watch
// per-file progress while Active Storage direct-uploads them, then the form
// submits normally carrying the signed blob ids. Without JS the same form
// posts multipart — one server path either way.
export default class extends Controller {
  static targets = ["form", "input", "zone", "progress"]

  connect() {
    this.onInitialize = (event) => this.uploadStarted(event)
    this.onProgress = (event) => this.uploadProgressed(event)
    this.onError = (event) => this.uploadFailed(event)
    this.element.addEventListener("direct-upload:initialize", this.onInitialize)
    this.element.addEventListener("direct-upload:progress", this.onProgress)
    this.element.addEventListener("direct-upload:error", this.onError)
  }

  disconnect() {
    this.element.removeEventListener("direct-upload:initialize", this.onInitialize)
    this.element.removeEventListener("direct-upload:progress", this.onProgress)
    this.element.removeEventListener("direct-upload:error", this.onError)
  }

  choose() {
    this.inputTarget.click()
  }

  changed() {
    this.submit()
  }

  dragOver(event) {
    event.preventDefault()
    this.zoneTarget.classList.add("border-primary-500", "bg-primary-100/50")
  }

  dragLeave(event) {
    event.preventDefault()
    this.zoneTarget.classList.remove("border-primary-500", "bg-primary-100/50")
  }

  drop(event) {
    event.preventDefault()
    this.zoneTarget.classList.remove("border-primary-500", "bg-primary-100/50")

    const images = Array.from(event.dataTransfer.files).filter((file) => file.type.startsWith("image/"))
    if (images.length === 0) return

    const transfer = new DataTransfer()
    images.forEach((file) => transfer.items.add(file))
    this.inputTarget.files = transfer.files
    this.submit()
  }

  submit() {
    if (this.inputTarget.files.length === 0) return

    this.zoneTarget.classList.add("pointer-events-none", "opacity-60")
    this.formTarget.requestSubmit()
  }

  uploadStarted(event) {
    const { id, file } = event.detail
    this.progressTarget.classList.remove("hidden")
    this.progressTarget.insertAdjacentHTML("beforeend", `
      <div class="flex items-center gap-2 text-xs text-soft" id="direct-upload-${id}">
        <span class="min-w-0 flex-1 truncate">${this.escape(file.name)}</span>
        <span class="h-1.5 w-32 overflow-hidden rounded-full bg-stone-200">
          <span class="block h-full w-0 rounded-full bg-primary-500 transition-all" data-progress></span>
        </span>
      </div>
    `)
  }

  uploadProgressed(event) {
    const { id, progress } = event.detail
    const bar = this.progressTarget.querySelector(`#direct-upload-${id} [data-progress]`)
    if (bar) bar.style.width = `${progress}%`
  }

  uploadFailed(event) {
    event.preventDefault()
    const { id, error } = event.detail
    const row = this.progressTarget.querySelector(`#direct-upload-${id}`)
    if (row) row.insertAdjacentHTML("beforeend", `<span class="text-red-600">${this.escape(String(error))}</span>`)
  }

  escape(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
