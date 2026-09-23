import { Controller } from "@hotwired/stimulus"

// Keeps the screen on while the in-store list is open: a phone that locks
// between aisles makes you unlock it with a basket in one hand. Where the
// browser has no Wake Lock, nothing happens.
export default class extends Controller {
  connect() {
    this.request = this.request.bind(this)
    this.request()
    document.addEventListener("visibilitychange", this.request)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.request)
    this.lock?.release().catch(() => {})
  }

  async request() {
    if (!("wakeLock" in navigator) || document.visibilityState !== "visible") return

    try {
      this.lock = await navigator.wakeLock.request("screen")
    } catch {
      // Denied (battery saver, an iframe) — the list works the same.
    }
  }
}
