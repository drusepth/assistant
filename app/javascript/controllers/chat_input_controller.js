import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The chat composer, attached to the form. The draft box grows with its
// content up to a cap; Enter sends and Shift+Enter breaks the line (see
// `keyboard` below for how a touch device with a real keyboard is told from
// one without); quick-reply chips send a canned turn without eating a typed
// draft. The textarea itself is [data-turbo-permanent] so a half-typed draft
// survives the page refresh that delivers the tutor's reply — which is why a
// *successful* send has to clear it here.
//
// The send button is dimmed on an empty draft, but only ever on top of the
// server's own [data-locked] (a reply is in flight): the markup ships
// enabled, so a composer with no JS still sends.
//
// It also owns the offline queue — see the block above `enqueue`.

// Keys a virtual keyboard essentially never emits. Seeing one is the only
// honest evidence that a coarse-pointer device has a real keyboard attached;
// arrows are left out on purpose, since some Android IMEs do send them.
const HARDWARE_KEYS = new Set([
  "Tab", "Escape", "Control", "Alt", "Meta", "PageUp", "PageDown", "Home", "End"
])
const KEYBOARD_STORAGE_KEY = "chat:hardware-keyboard"
const QUEUE_LIMIT = 20

export default class extends Controller {
  static targets = ["input", "send", "pendingTemplate", "offline"]
  static values = {
    maxHeight: { type: Number, default: 240 },
    queueKey: String
  }

  connect() {
    this.grow()
    this.refreshSend()
    this.refreshOffline()
    this.renderPending()
    this.flush()
    if (this.keyboard) this.inputTarget.focus()
  }

  // A hardware keyboard is learned, not guessed. `(pointer: coarse)` alone
  // called every tablet-with-a-keyboard-case a touch device, so Enter never
  // sent there and the only way to send was the button — while `(any-pointer:
  // fine)` would have gone wrong the other way and broken newlines on a phone
  // with a stylus. So: coarse pointers start with Enter as newline, and the
  // first press of a key no virtual keyboard produces flips it, for good.
  noteKeyboard(event) {
    if (this.hardwareKeyboard || !HARDWARE_KEYS.has(event.key)) return

    this.hardwareKeyboard = true
    try { localStorage.setItem(KEYBOARD_STORAGE_KEY, "1") } catch {}
  }

  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    const shortcut = event.metaKey || event.ctrlKey
    if (!this.keyboard && !shortcut) return

    event.preventDefault()
    if (this.inputTarget.value.trim() && !this.sendBlocked) this.send()
  }

  quickReply(event) {
    if (this.sendBlocked) return

    this.stashedDraft = this.inputTarget.value
    this.inputTarget.value = event.params.text
    this.send()
  }

  grow() {
    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = `${Math.min(input.scrollHeight, this.maxHeightValue)}px`
    this.refreshSend()
  }

  send() {
    this.element.requestSubmit()
  }

  refreshSend() {
    if (!this.hasSendTarget || this.sendBlocked) return

    this.sendTarget.disabled = this.inputTarget.value.trim() === ""
  }

  get sendBlocked() {
    return this.hasSendTarget && this.sendTarget.hasAttribute("data-locked")
  }

  get keyboard() {
    if (!window.matchMedia("(pointer: coarse)").matches) return true

    return this.hardwareKeyboard
  }

  get hardwareKeyboard() {
    if (this._hardwareKeyboard === undefined) {
      try {
        this._hardwareKeyboard = localStorage.getItem(KEYBOARD_STORAGE_KEY) === "1"
      } catch {
        this._hardwareKeyboard = false
      }
    }
    return this._hardwareKeyboard
  }

  set hardwareKeyboard(value) {
    this._hardwareKeyboard = value
  }

  // ── The offline queue ────────────────────────────────────────────────────
  //
  // A phone loses signal in lifts, on trains, and in the basement flat where
  // somebody is actually asking the money coach a question. Without this, a
  // send in that moment is a browser error and the sentence is gone.
  //
  // So a message that can't leave is kept: held in memory, mirrored to
  // localStorage so it survives the tab, and shown in the transcript as a
  // dimmed bubble that says what happened. It goes out by itself when the
  // connection returns, and by hand from the bubble's own Retry.
  //
  // The text sits in localStorage in the clear, which is a real (if small)
  // disclosure on a shared device — it is the same-origin store on the user's
  // own machine, it is cleared the moment the message is delivered or
  // discarded, and the alternative is losing what they wrote. Named here so
  // the tradeoff is a choice rather than an accident.

  beforeSubmit(event) {
    if (navigator.onLine || this.flushing) return
    if (!this.inputTarget.value.trim()) return

    // Preempting Turbo: its submit handler runs on the document in the
    // bubble phase, after this one, and honors defaultPrevented.
    event.preventDefault()
    this.enqueue(this.inputTarget.value)
    this.clearDraft()
  }

  reset(event) {
    // A submission that never reached the server has no fetchResponse — that
    // is the network failing, not the app rejecting the turn, so the message
    // is kept rather than lost. A 4xx is a real answer and falls through.
    if (!event.detail.success && !event.detail.fetchResponse && !this.flushing) {
      this.enqueue(this.inputTarget.value)
      this.clearDraft()
      this.refreshOffline()
      return
    }

    if (!event.detail.success) return

    this.inputTarget.value = this.stashedDraft || ""
    this.stashedDraft = null
    this.grow()
    this.refreshSend()
    if (this.keyboard) this.inputTarget.focus()
  }

  discard(event) {
    this.pending = this.pending.filter((item) => item.id !== event.params.id)
    this.persist()
    this.renderPending()
  }

  retry(event) {
    const item = this.pending.find((entry) => entry.id === event.params.id)
    if (item) delete item.failed
    this.persist()
    this.renderPending()
    this.flush()
  }

  async flush() {
    const next = () => this.pending.find((item) => !item.failed)
    if (this.flushing || !navigator.onLine || !next()) return

    this.flushing = true
    let delivered = 0

    try {
      let item
      while ((item = next())) {
        const outcome = await this.deliver(item.text)
        // "kept" is the network failing again — stop, change nothing, and
        // wait for the next `online` or a hand retry.
        if (outcome === "kept") break

        if (outcome === "sent") {
          this.pending = this.pending.filter((entry) => entry !== item)
          delivered += 1
        } else {
          // The server answered and said no — the run is gone, or isn't a
          // live conversation. Retrying forever would spin, and dropping it
          // would take the user's words with it, so the bubble stays and
          // says so.
          item.failed = true
        }
        this.persist()
      }
    } finally {
      this.flushing = false
      this.renderPending()
      // One refresh at the end, not one per message: the delivered turns are
      // on the server now, and a morph is what brings them into the
      // transcript (and takes the placeholder bubbles back out).
      if (delivered) Turbo.visit(window.location.href, { action: "replace" })
    }
  }

  async deliver(text) {
    const body = new FormData()
    body.append("content", text)

    let response
    try {
      response = await fetch(this.queueKeyValue, {
        method: "POST",
        body: body,
        credentials: "same-origin",
        headers: { "X-CSRF-Token": this.csrfToken, "Accept": "text/html" }
      })
    } catch {
      return "kept"
    }

    if (response.ok) return "sent"
    return response.status >= 400 && response.status < 500 ? "rejected" : "kept"
  }

  enqueue(text) {
    const content = text.trim()
    if (!content || this.pending.length >= QUEUE_LIMIT) return

    this.pending.push({ id: `${Date.now()}-${this.pending.length}`, text: content })
    this.persist()
    this.renderPending()
  }

  renderPending() {
    const transcript = document.getElementById("chat-transcript")
    if (!transcript || !this.hasPendingTemplateTarget) return

    transcript.querySelectorAll("[data-pending-bubble]").forEach((node) => node.remove())

    this.pending.forEach((item) => {
      const node = this.pendingTemplateTarget.content.firstElementChild.cloneNode(true)
      node.querySelector("[data-pending-text]").textContent = item.text
      node.querySelector("[data-pending-status]").textContent =
        item.failed ? "Couldn't send" : "Waiting to send"
      node.querySelectorAll("[data-chat-input-id-param]")
        .forEach((button) => button.setAttribute("data-chat-input-id-param", item.id))
      transcript.appendChild(node)
    })

    this.refreshOffline()
  }

  refreshOffline() {
    if (!this.hasOfflineTarget) return

    const waiting = this.pending.some((item) => !item.failed)
    this.offlineTarget.hidden = navigator.onLine && !waiting
    this.offlineTarget.textContent = navigator.onLine
      ? "Back online — sending what's waiting…"
      : "Offline. Anything you send is kept here and goes out when you're back."
  }

  get pending() {
    if (!this._pending) {
      try {
        this._pending = JSON.parse(localStorage.getItem(this.storageKey) || "[]")
      } catch {
        this._pending = []
      }
    }
    return this._pending
  }

  set pending(value) {
    this._pending = value
  }

  persist() {
    try {
      if (this.pending.length) {
        localStorage.setItem(this.storageKey, JSON.stringify(this.pending))
      } else {
        localStorage.removeItem(this.storageKey)
      }
    } catch {}
  }

  get storageKey() {
    return `chat-queue:${this.queueKeyValue}`
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  clearDraft() {
    this.inputTarget.value = ""
    this.grow()
    this.refreshSend()
  }
}
