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
  static targets = [
    "input", "send", "offline", "suggestions", "token",
    "optimisticTemplate", "pendingTemplate", "thinkingTemplate"
  ]
  static values = {
    maxHeight: { type: Number, default: 240 },
    queueKey: String
  }

  connect() {
    this.restoreDraft()
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
    this.saveDraft()
  }

  send() {
    this.element.requestSubmit()
  }

  refreshSend() {
    const drafting = this.inputTarget.value.trim() !== ""

    // Once you have decided what to say, a row of canned openings is in the
    // way — and on a phone it is in the way of the conversation itself.
    if (this.hasSuggestionsTarget) this.suggestionsTarget.hidden = drafting

    if (!this.hasSendTarget || this.sendBlocked) return

    this.sendTarget.disabled = !drafting
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

  // ── Optimistic send (D-chat-optimistic) ─────────────────────────────────
  //
  // The turn is drawn, the composer cleared and locked, and the reply's dots
  // started — all before the fetch leaves. Everything here is *only* about the
  // gap between the tap and the response: the server still answers with a
  // redirect, so the morph that follows is what makes the page true.
  //
  // The two are reconciled by a token rather than by luck. The bubble is drawn
  // with `chat-msg-<token>`, the form posts the token, the server stores it and
  // renders the real turn under the same id — so the morph matches them and
  // nothing flickers. Grouping is the one thing the client can't know, so a
  // sent turn always draws standing alone and settles into its group when the
  // morph lands.
  mintToken() {
    return `c${Date.now().toString(36)}${Math.floor(Math.random() * 1e6).toString(36)}`
  }

  draw(text, token) {
    const transcript = this.transcript
    if (!transcript || !this.hasOptimisticTemplateTarget) return

    const bubble = this.optimisticTemplateTarget.content.firstElementChild.cloneNode(true)
    if (token) bubble.id = `chat-msg-${token}`
    bubble.querySelector("[data-optimistic-text]").textContent = text
    transcript.appendChild(bubble)

    // The wait starts now too, not when the server gets back to us.
    if (this.hasThinkingTemplateTarget && !document.getElementById("chat-thinking")) {
      transcript.appendChild(this.thinkingTemplateTarget.content.firstElementChild.cloneNode(true))
    }

    this.lock()
  }

  // Locking here rather than waiting for the server is what stops a second
  // send landing in the gap. The morph re-renders the button from the truth a
  // moment later, so this is never the last word.
  lock() {
    if (!this.hasSendTarget) return

    this.sendTarget.setAttribute("data-locked", "true")
    this.sendTarget.disabled = true
  }

  get transcript() {
    return document.getElementById("chat-transcript")
  }

  // ── Drafts ──────────────────────────────────────────────────────────────
  //
  // [data-turbo-permanent] carries a half-typed message across the morph that
  // delivers a reply, but not across a navigation — walk away mid-sentence and
  // the sentence was gone. Same store and same key shape as the offline queue.

  saveDraft() {
    const text = this.inputTarget.value
    try {
      if (text.trim()) localStorage.setItem(this.draftKey, text)
      else localStorage.removeItem(this.draftKey)
    } catch {}
  }

  restoreDraft() {
    if (this.inputTarget.value.trim()) return

    try {
      const draft = localStorage.getItem(this.draftKey)
      if (draft) this.inputTarget.value = draft
    } catch {}
  }

  clearDraft() {
    this.inputTarget.value = ""
    try { localStorage.removeItem(this.draftKey) } catch {}
    this.grow()
    this.refreshSend()
  }

  get draftKey() {
    return `chat-draft:${this.queueKeyValue}`
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

  // Two moments, and the order is the whole trick.
  //
  // `submit` is the last point at which the form can be stopped (Turbo's own
  // handler runs on the document in the bubble phase, after this one, and
  // honors defaultPrevented) *and* the last point at which a field can still be
  // changed — Turbo captures the body when it constructs the submission, which
  // is after this and before turbo:submit-start. So the token is stamped here.
  //
  // Clearing the composer here instead would post an empty message: the
  // textarea is part of that same body.
  beforeSubmit(event) {
    if (this.flushing) return

    const text = this.inputTarget.value
    if (!text.trim()) return

    if (!navigator.onLine) {
      event.preventDefault()
      this.enqueue(text)
      this.clearDraft()
      return
    }

    if (this.hasTokenTarget) this.tokenTarget.value = this.mintToken()
  }

  // ...and by here the body is captured, so the composer can be emptied and
  // the turn drawn under the token that just went out with it.
  submitStart() {
    if (this.flushing) return

    const text = this.inputTarget.value
    if (!text.trim()) return

    this.draw(text, this.hasTokenTarget ? this.tokenTarget.value : null)
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

    // The composer was cleared when the turn was drawn; all that is left is
    // giving back a draft a quick-reply chip pushed aside.
    if (this.stashedDraft) {
      this.inputTarget.value = this.stashedDraft
      this.stashedDraft = null
      this.saveDraft()
    }
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

}
