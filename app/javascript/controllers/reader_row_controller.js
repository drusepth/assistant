import { Controller } from "@hotwired/stimulus"

// A row in the river: opening it, and the two thumb gestures that clear it.
//
// **Opening happens here.** The old row's only way into an article was a new
// tab, which meant a four-hundred item river could be triaged but never
// read — you left the app once per item. A plain click now expands the row
// in place: the blurb, and the verbs at a size a thumb can hit. That one
// change is what lets the collapsed row drop its preview, its verbs and its
// chip, which is where the density came back from.
//
// The headline stays a real `<a href>` so a modified or middle click still
// stashes a background tab natively — that reader is going to the source and
// it is not our business to redirect them, so their row marks itself read
// *and leaves the unread list*, exactly as it always did. Only the plain
// left click is intercepted.
//
// **The gestures** are the phone's answer to three 12px text links: swipe
// left marks read, swipe right saves. Both end in pressing the row's own
// ordinary button, so the write, the Turbo re-render and the Undo line all
// go through the one code path the buttons already use — this controller
// never learns a URL.
const SWIPE_TRIGGER = 64 // px of travel before a swipe counts
const SWIPE_SLOP = 20 // px of vertical drift that makes it a scroll instead
const SWIPE_START = 10 // px before we commit to horizontal and stop scrolling

export default class extends Controller {
  static targets = ["panel"]
  static values = { readUrl: String, dismissUrl: String, read: Boolean }

  connect() {
    this.element.addEventListener("touchstart", this.onStart, { passive: true })
    this.element.addEventListener("touchmove", this.onMove, { passive: false })
    this.element.addEventListener("touchend", this.onEnd)
    this.element.addEventListener("touchcancel", this.onEnd)
  }

  disconnect() {
    this.element.removeEventListener("touchstart", this.onStart)
    this.element.removeEventListener("touchmove", this.onMove)
    this.element.removeEventListener("touchend", this.onEnd)
    this.element.removeEventListener("touchcancel", this.onEnd)
  }

  // ---- opening -----------------------------------------------------------

  // A click anywhere on the line that isn't a control of its own.
  toggle(event) {
    if (event.target.closest("a, button, input, label, form")) return
    this.setOpen(!this.open)
  }

  // The headline link. Plain click expands; anything else is somebody
  // stashing a tab, so the browser does its thing and the row leaves.
  openOrExpand(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) {
      this.request(this.dismissUrlValue)
      return
    }
    event.preventDefault()
    this.setOpen(!this.open)
  }

  get open() {
    return this.element.classList.contains("is-open")
  }

  setOpen(next) {
    this.element.classList.toggle("is-open", next)
    // Opening something is reading it. The row is asked to come back *open*
    // (`from=expand`), so the re-render this triggers doesn't shut what you
    // just opened — and unlike a click through to the source it stays in the
    // unread list, because you haven't left it yet.
    if (next && !this.readValue) this.request(this.readUrlValue)
    if (next) this.element.dispatchEvent(new CustomEvent("reader:opened", { bubbles: true }))
  }

  // ---- gestures ----------------------------------------------------------

  onStart = (event) => {
    if (event.touches.length !== 1) return
    const touch = event.touches[0]
    this.from = { x: touch.clientX, y: touch.clientY }
    this.axis = null
  }

  onMove = (event) => {
    if (!this.from || event.touches.length !== 1) return

    const touch = event.touches[0]
    const dx = touch.clientX - this.from.x
    const dy = touch.clientY - this.from.y

    // Decide once, on the first meaningful movement, whether this is a swipe
    // or a scroll — and never take it back. Re-deciding mid-gesture is what
    // makes a list feel like it is fighting your thumb.
    if (this.axis === null) {
      if (Math.abs(dy) > SWIPE_SLOP) { this.axis = "scroll"; return }
      if (Math.abs(dx) < SWIPE_START) return
      this.axis = "swipe"
    }
    if (this.axis !== "swipe") return

    // The page must not scroll under a swipe.
    event.preventDefault()
    this.element.style.transform = `translateX(${dx}px)`
    this.element.classList.toggle("reader-row-read", dx < -SWIPE_TRIGGER)
    this.element.classList.toggle("reader-row-save", dx > SWIPE_TRIGGER)
  }

  onEnd = () => {
    if (!this.from) return

    const travelled = parseFloat(this.element.style.transform.replace(/[^-\d.]/g, "")) || 0
    this.element.style.transform = ""
    this.from = null

    if (this.axis !== "swipe") return this.clearSwipeHint()

    if (travelled < -SWIPE_TRIGGER) this.press(this.readValue ? "Unread" : "Read")
    else if (travelled > SWIPE_TRIGGER) this.press("Save")
    else this.clearSwipeHint()
  }

  clearSwipeHint() {
    this.element.classList.remove("reader-row-read", "reader-row-save")
  }

  // ---- plumbing ----------------------------------------------------------

  // Press one of the row's own buttons by name, so a gesture and a tap take
  // exactly the same path through the server.
  press(label) {
    const button = [...this.element.querySelectorAll("button")]
      .find(candidate => candidate.textContent.trim() === label)
    if (button) button.click()
    else this.clearSwipeHint()
  }

  // Ask the server for the same Turbo Stream the Read button would have
  // produced, so the row updates itself in place through one code path.
  request(url) {
    if (!url) return

    fetch(url, {
      method: "PATCH",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
      },
      credentials: "same-origin"
    })
      .then(response => (response.ok ? response.text() : null))
      .then(html => { if (html) window.Turbo.renderStreamMessage(html) })
      // A failed mark-read is not worth interrupting somebody's reading for:
      // the row is still there to press.
      .catch(() => {})
  }
}
