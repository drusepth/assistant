import { Controller } from "@hotwired/stimulus"

// Keyboard navigation for the river (docs/READER.md): `j`/`k` to move,
// `o` or Enter to open, `m` to mark read, `s` to save. Google Reader's
// keys, which is the point — the people who miss that reader miss these
// four, and a list you can only operate with a pointer is a list you scroll
// rather than one you process.
//
// The selection lives in the DOM (a `data-river-current` attribute) rather
// than in an index: rows arrive and leave over Turbo as they are read, and
// an index into a list that changed under you selects the wrong story.
export default class extends Controller {
  static targets = ["row"]

  connect() {
    this.onKey = this.onKey.bind(this)
    document.addEventListener("keydown", this.onKey)
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
      case "j": this.move(1); break
      case "k": this.move(-1); break
      case "o":
      case "Enter": this.open(); break
      case "m": this.press("Read"); break
      case "s": this.press("Save"); break
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

  open() {
    // The row's own headline link, clicked for real — so it opens in a new
    // tab, carries the same rel, and marks itself read through exactly the
    // path a pointer would have taken.
    this.current?.querySelector("h3 a")?.click()
  }

  // The verbs are ordinary buttons in the row; pressing one by name keeps
  // this controller from knowing any URL.
  press(label) {
    const button = [...(this.current?.querySelectorAll("button") || [])]
      .find(candidate => candidate.textContent.trim() === label)
    button?.click()
  }

  get current() {
    return this.element.querySelector("[data-river-current]")
  }
}
