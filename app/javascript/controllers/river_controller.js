import { Controller } from "@hotwired/stimulus"

// Keyboard navigation for the river (docs/READER.md): `j`/`k` to move, `o`
// to open at the source, `m` to mark read, `s` to save. Google Reader's
// keys, which is the point — the people who miss that reader miss these
// four, and a list you can only operate with a pointer is a list you scroll
// rather than one you process.
//
// Four more have been added, and each one closes a hole the four left:
//
//   Enter  expand the row in place. This is the one that was actually
//          missing. `o` throws you to a new tab, so a four-hundred item
//          river could only ever be triaged; Reader's real trick was that
//          you could *read* in it.
//   r      check the feeds now, without reaching for the mouse.
//   A      mark the feed you are currently looking at read — the middle
//          ground between one item and the whole river, which had no key
//          and no button.
//   ?      the sheet, because four shortcuts nobody can discover are zero
//          shortcuts. `n`/`p` alias `j`/`k` for the muscle memory that
//          came from elsewhere.
//
// The selection lives in the DOM (a `data-river-current` attribute) rather
// than in an index: rows arrive and leave over Turbo as they are read, and
// an index into a list that changed under you selects the wrong story.
export default class extends Controller {
  static targets = ["row", "sheet"]

  connect() {
    this.onKey = this.onKey.bind(this)
    document.addEventListener("keydown", this.onKey)
    this.restoreDensity()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
  }

  onKey(event) {
    // Never steal a key from someone typing, and never from a shortcut.
    if (event.metaKey || event.ctrlKey || event.altKey) return
    const tag = event.target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || event.target.isContentEditable) return

    switch (event.key) {
      case "j": case "n": this.move(1); break
      case "k": case "p": this.move(-1); break
      case "Enter": this.expand(); break
      case "o": this.open(); break
      case "m": this.press("Read") || this.press("Unread"); break
      case "s": this.press("Save") || this.press("Unsave"); break
      case "r": this.click("[data-river-refresh]"); break
      case "A": this.click("[data-river-read-all]"); break
      case "1": this.setDensity("compact"); break
      case "2": this.setDensity("comfortable"); break
      case "?": this.toggleSheet(); break
      case "Escape": this.closeSheet(); break
      default: return
    }
    event.preventDefault()
  }

  move(step) {
    const rows = this.rowTargets
    if (rows.length === 0) return

    const index = rows.indexOf(this.current)
    // No selection yet: `j` starts at the top, `k` at the bottom.
    const next = index === -1 ? (step > 0 ? 0 : rows.length - 1) : index + step
    this.select(rows[Math.max(0, Math.min(next, rows.length - 1))])
  }

  select(row) {
    if (!row) return

    this.current?.removeAttribute("data-river-current")
    row.setAttribute("data-river-current", "")
    // `nearest` so a row already on screen doesn't yank the page around.
    row.scrollIntoView({ block: "nearest" })
  }

  // Expanding is the row's own business — this only says which row.
  expand() {
    if (!this.current) return this.move(1)

    this.rowController?.setOpen(!this.current.classList.contains("is-open"))
  }

  get rowController() {
    if (!this.current) return null
    return this.application.getControllerForElementAndIdentifier(this.current, "reader-row")
  }

  // Two densities, remembered per browser. Compact is the river's own shape:
  // headline, source, age. Comfortable brings the opening words down onto
  // the phone row for somebody browsing rather than triaging — which is a
  // real second mode, and the reason the blurb being unconditionally on at
  // one width and unconditionally off at the other was never right.
  setDensity(value) {
    this.element.classList.toggle("river-comfortable", value === "comfortable")
    try { localStorage.setItem("reader:density", value) } catch { /* private window */ }
  }

  restoreDensity() {
    let stored = null
    try { stored = localStorage.getItem("reader:density") } catch { /* private window */ }
    if (stored) this.element.classList.toggle("river-comfortable", stored === "comfortable")
  }

  // Going to the source. Same outcome as a modified click on the headline:
  // the tab opens, and the row marks itself read and leaves the unread list,
  // because you have gone to read it somewhere else.
  open() {
    const link = this.current?.querySelector(".reader-title")
    if (!link?.href) return

    this.rowController?.request(this.rowController.dismissUrlValue)
    window.open(link.href, "_blank", "noopener,noreferrer")
  }

  // The verbs are ordinary buttons in the row; pressing one by name keeps
  // this controller from knowing any URL. Returns whether it found one, so
  // a key can name a verb and its opposite and take whichever is there.
  press(label) {
    const button = [...(this.current?.querySelectorAll("button") || [])]
      .find(candidate => candidate.textContent.trim() === label)
    button?.click()
    return Boolean(button)
  }

  // A page-level control, pressed by name rather than by URL for the same
  // reason the row verbs are.
  click(selector) {
    document.querySelector(selector)?.click()
  }

  toggleSheet() {
    if (!this.hasSheetTarget) return
    this.sheetTarget.classList.toggle("hidden")
  }

  closeSheet() {
    this.sheetTarget?.classList.add("hidden")
  }

  // A click inside the sheet's card is not a click on its backdrop.
  stop(event) {
    event.stopPropagation()
  }

  get current() {
    return this.element.querySelector("[data-river-current]")
  }
}
