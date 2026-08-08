import { Controller } from "@hotwired/stimulus"

// Full-screen viewer over the photo grid: click a tile to open the large
// variant in place, arrow keys / buttons to move within the current page,
// Escape (or the backdrop) to close, and a link through to the photo's own
// page. Progressive enhancement — the tiles are ordinary links without it.
export default class extends Controller {
  static targets = ["item"]

  open(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()

    this.index = this.itemTargets.indexOf(event.currentTarget)
    this.build()
    this.show()
  }

  disconnect() {
    this.close()
  }

  build() {
    if (this.overlay) return

    this.overlay = document.createElement("div")
    this.overlay.className = "fixed inset-0 z-50 flex flex-col bg-black/95"
    this.overlay.innerHTML = `
      <div class="flex justify-end p-3">
        <button type="button" data-lightbox-close aria-label="Close"
                class="flex size-11 items-center justify-center rounded-full text-white/70 hover:bg-white/10 hover:text-white">✕</button>
      </div>
      <div class="relative flex min-h-0 flex-1 items-center justify-center px-14 pb-4" data-lightbox-stage>
        <button type="button" data-lightbox-prev aria-label="Previous photo"
                class="absolute left-2 top-1/2 flex size-11 -translate-y-1/2 items-center justify-center rounded-full text-2xl text-white/70 hover:bg-white/10 hover:text-white">‹</button>
        <img class="max-h-full max-w-full rounded-lg object-contain" data-lightbox-image alt="">
        <button type="button" data-lightbox-next aria-label="Next photo"
                class="absolute right-2 top-1/2 flex size-11 -translate-y-1/2 items-center justify-center rounded-full text-2xl text-white/70 hover:bg-white/10 hover:text-white">›</button>
      </div>
      <div class="flex items-center justify-between gap-3 px-5 pb-4 text-sm text-white/80">
        <span class="min-w-0 truncate" data-lightbox-caption></span>
        <a class="shrink-0 underline decoration-white/40 underline-offset-2 hover:text-white" data-lightbox-details>Details</a>
      </div>
    `
    this.overlay.querySelector("[data-lightbox-close]").addEventListener("click", () => this.close())
    this.overlay.querySelector("[data-lightbox-prev]").addEventListener("click", () => this.previous())
    this.overlay.querySelector("[data-lightbox-next]").addEventListener("click", () => this.next())
    this.overlay.addEventListener("click", (event) => {
      if (event.target === this.overlay || event.target.hasAttribute("data-lightbox-stage")) this.close()
    })

    this.onKeydown = (event) => {
      if (event.key === "Escape") this.close()
      if (event.key === "ArrowLeft") this.previous()
      if (event.key === "ArrowRight") this.next()
    }
    document.addEventListener("keydown", this.onKeydown)
    document.body.appendChild(this.overlay)
    document.body.style.overflow = "hidden"
  }

  show() {
    const item = this.itemTargets[this.index]
    this.overlay.querySelector("[data-lightbox-image]").src = item.dataset.largeUrl
    this.overlay.querySelector("[data-lightbox-image]").alt = item.dataset.caption
    this.overlay.querySelector("[data-lightbox-caption]").textContent = item.dataset.caption
    this.overlay.querySelector("[data-lightbox-details]").href = item.href

    for (const neighbor of [this.index - 1, this.index + 1]) {
      if (this.itemTargets[neighbor]) new Image().src = this.itemTargets[neighbor].dataset.largeUrl
    }
  }

  previous() {
    this.index = (this.index - 1 + this.itemTargets.length) % this.itemTargets.length
    this.show()
  }

  next() {
    this.index = (this.index + 1) % this.itemTargets.length
    this.show()
  }

  close() {
    if (!this.overlay) return

    document.removeEventListener("keydown", this.onKeydown)
    this.overlay.remove()
    this.overlay = null
    document.body.style.overflow = ""
  }
}
