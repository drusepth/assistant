import { Controller } from "@hotwired/stimulus"

// Read-on-scroll, and the ledger that makes it safe (D-reader-density).
//
// A four-hundred item backlog used to have exactly two outcomes: four
// hundred deliberate clicks, or Mark all read. Anybody sane picked the
// second, which throws the pile away unseen — so the reader's own scrolling
// is what marks things read now, the way every native reader has worked for
// a decade.
//
// The two things that make that acceptable rather than alarming are both
// here. A row must be *fully* past the top of the viewport and stay there
// for a beat, so a fast flick to reach something further down doesn't eat
// what it flew over; and every batch is undoable, in one press, from a bar
// that names the number.
//
// The rail under the header is the other half: a backlog with no visible
// floor is a guilt pile, and watching it fill is what turns four hundred
// unread into a session with an end.
const DWELL = 900 // ms a row must stay past the top before it counts
const SETTLE = 550 // ms of quiet before a batch is sent
const UNDO_MS = 7000 // how long the bar stays before it fades

export default class extends Controller {
  static targets = ["row", "rail", "count", "bar", "barText"]
  static values = { readUrl: String, unreadUrl: String, total: Number }

  connect() {
    this.cleared = 0
    this.dwelling = new Map()
    this.batch = new Map()
    this.lastBatch = []

    this.observer = new IntersectionObserver(this.onCross, { threshold: 0 })
    this.observeAll()
    // Rows arrive and leave over Turbo all the time here, so the observer is
    // re-pointed whenever the list changes rather than only on connect.
    this.watcher = new MutationObserver(() => this.observeAll())
    this.watcher.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
    this.watcher?.disconnect()
    clearTimeout(this.settle)
    clearTimeout(this.hide)
    this.dwelling.forEach(clearTimeout)
  }

  observeAll() {
    this.rowTargets.forEach(row => {
      if (row.dataset.ledgerWatched) return
      row.dataset.ledgerWatched = "1"
      this.observer.observe(row)
    })
  }

  onCross = (entries) => {
    for (const entry of entries) {
      const row = entry.target

      // Back on screen — whatever it was serving, it isn't past any more.
      if (entry.isIntersecting || entry.boundingClientRect.bottom > 0) {
        clearTimeout(this.dwelling.get(row))
        this.dwelling.delete(row)
        continue
      }
      if (row.dataset.readerRowReadValue === "true") continue
      if (this.dwelling.has(row) || this.batch.has(row)) continue

      this.dwelling.set(row, setTimeout(() => this.enqueue(row), DWELL))
    }
  }

  enqueue(row) {
    this.dwelling.delete(row)
    const id = row.dataset.ledgerIdParam
    if (!id || row.dataset.readerRowReadValue === "true") return

    this.batch.set(row, id)
    // Mark it here rather than waiting for the round trip: the row is off
    // screen, so the only thing a delay could do is let it be counted twice.
    row.dataset.readerRowReadValue = "true"
    row.classList.add("is-read")

    clearTimeout(this.settle)
    this.settle = setTimeout(() => this.flush(), SETTLE)
  }

  flush() {
    if (this.batch.size === 0) return

    const rows = [...this.batch.keys()]
    const ids = [...this.batch.values()]
    this.batch.clear()

    this.post(this.readUrlValue, ids)
      .then(() => {
        this.lastBatch = { rows, ids }
        this.cleared += ids.length
        this.paint()
        this.announce(`${ids.length} marked read`)
      })
      // The write failed, so the rows are not read and must not look it.
      .catch(() => rows.forEach(row => {
        row.dataset.readerRowReadValue = "false"
        row.classList.remove("is-read")
      }))
  }

  undo() {
    const { rows, ids } = this.lastBatch
    if (!ids?.length) return

    this.lastBatch = []
    this.post(this.unreadUrlValue, ids).then(() => {
      rows.forEach(row => {
        row.dataset.readerRowReadValue = "false"
        row.classList.remove("is-read")
      })
      this.cleared = Math.max(0, this.cleared - ids.length)
      this.paint()
      this.dismiss()
    })
  }

  paint() {
    const total = this.totalValue || 1
    const pct = Math.min(100, Math.round((this.cleared / total) * 100))
    if (this.hasRailTarget) this.railTarget.style.width = `${pct}%`
    if (this.hasCountTarget) {
      this.countTarget.textContent =
        this.cleared > 0 ? `${this.cleared} cleared · ${Math.max(0, total - this.cleared)} left` : ""
    }
  }

  announce(text) {
    if (!this.hasBarTarget) return

    this.barTextTarget.textContent = text
    this.barTarget.classList.remove("hidden")
    clearTimeout(this.hide)
    this.hide = setTimeout(() => this.dismiss(), UNDO_MS)
  }

  dismiss() {
    this.barTarget?.classList.add("hidden")
  }

  post(url, ids) {
    const body = new URLSearchParams()
    ids.forEach(id => body.append("ids[]", id))

    return fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
      },
      credentials: "same-origin",
      body
    }).then(response => {
      if (!response.ok) throw new Error(response.status)
      return response
    })
  }
}
