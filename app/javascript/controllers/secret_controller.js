import { Controller } from "@hotwired/stimulus"

// Vault reveals (PASSWORDS_PLAN §4.4): secrets are fetched per click from a
// POST no-store endpoint, never rendered server-side. Copy overwrites the
// clipboard after 45s (best effort — another copy elsewhere wins, and we
// only clear if it still holds our value). Reveal swaps into the slot span
// and hides again on a second click or when the page is left.
export default class extends Controller {
  static values = { url: String }

  disconnect() { this.#restoreSlots() }

  async copy(event) {
    const button = event.currentTarget
    const data = await this.#fetch(button.dataset.secretFieldParam, button)
    if (data?.value) this.#toClipboard(data.value, button)
  }

  copyText(event) {
    const button = event.currentTarget
    this.#toClipboard(button.dataset.secretTextParam, button)
  }

  async toggle(event) {
    const button = event.currentTarget
    const field = button.dataset.secretFieldParam
    const slot = this.element.querySelector(`[data-secret-slot="${field}"]`)
    if (!slot) return

    if (slot.dataset.revealed === "1") {
      this.#mask(slot)
      button.textContent = "reveal"
      return
    }

    const data = await this.#fetch(field, button)
    if (data?.value) {
      if (!slot.dataset.masked) slot.dataset.masked = slot.textContent
      slot.textContent = data.value
      slot.dataset.revealed = "1"
      button.textContent = "hide"
    }
  }

  async totp(event) {
    const button = event.currentTarget
    const data = await this.#fetch("totp", button)
    if (!data?.code) return

    this.#toClipboard(data.code, null)
    button.textContent = data.code
    clearTimeout(this.totpTimer)
    // Refresh once when the window rolls over, then let it go stale visibly.
    this.totpTimer = setTimeout(async () => {
      const next = await this.#fetch("totp", button)
      if (next?.code) button.textContent = next.code
    }, (data.seconds_remaining || 30) * 1000)
  }

  async #fetch(field, button) {
    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded"
      },
      body: new URLSearchParams({ field })
    })
    if (response.status === 401) { this.#flash(button, "Locked"); return null }
    if (!response.ok) { this.#flash(button, "Unavailable"); return null }
    return response.json()
  }

  #toClipboard(text, button) {
    navigator.clipboard.writeText(text)
    if (button) this.#flash(button, "Copied!")
    clearTimeout(this.clipboardTimer)
    this.clipboardTimer = setTimeout(async () => {
      try {
        if (await navigator.clipboard.readText() === text) await navigator.clipboard.writeText("")
      } catch { /* clipboard read needs focus/permission; clearing is best-effort */ }
    }, 45000)
  }

  #flash(button, message) {
    if (!button) return
    const original = button.textContent
    button.textContent = message
    setTimeout(() => { button.textContent = original }, 1500)
  }

  #mask(slot) {
    slot.textContent = slot.dataset.masked || "••••••••"
    delete slot.dataset.revealed
  }

  #restoreSlots() {
    this.element.querySelectorAll('[data-secret-slot][data-revealed="1"]').forEach(slot => this.#mask(slot))
  }
}
