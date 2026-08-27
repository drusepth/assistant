import { Controller } from "@hotwired/stimulus"

// Explore's instant filter (D-feed-explore).
//
// The search field is a real GET form and works with this controller absent:
// type, press Enter, the server filters and hands back a URL you can keep.
// What this adds is the narrowing on the keystroke, which is the difference
// between a shelf you scan and a shelf you scroll. Every row carries what it
// shows in `data-shelf-haystack`, so filtering a hundred and fifty rows is a
// hundred and fifty `String.includes` calls.
//
// Rows and their topic cards narrow together: a topic heading left standing
// over nothing is a lie about what the shelf holds, and a "Follow all 4"
// button over one visible row is a worse one — so an emptied card goes.
export default class extends Controller {
  static targets = ["input", "row", "group", "empty", "count"]
  static values = { total: Number }

  connect() {
    // A morph, a bfcache restore, or a browser that kept the field's text
    // can all land us here with a query typed and every row shown.
    this.filter()
  }

  filter() {
    const query = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    let visible = 0

    this.rowTargets.forEach((row) => {
      const match = query === "" || (row.dataset.shelfHaystack || "").includes(query)
      // Display rather than the `hidden` attribute: these rows carry a
      // `flex` class, which outranks the user-agent's `[hidden]` rule and
      // would leave every "hidden" row on screen.
      row.style.display = match ? "" : "none"
      if (match) visible++
    })

    this.groupTargets.forEach((group) => {
      const shown = Array.from(group.querySelectorAll("[data-shelf-target~='row']"))
        .some((row) => row.style.display !== "none")
      group.style.display = shown ? "" : "none"
    })

    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", visible > 0)
    if (this.hasCountTarget) this.countTarget.textContent = this.phrase(visible)
  }

  // Mirrors what the server renders into the same slot, so the number
  // doesn't change shape the moment you touch the keyboard.
  phrase(visible) {
    const total = this.hasTotalValue ? this.totalValue : visible
    if (visible === total) return `${total} source${total === 1 ? "" : "s"}`
    return `${visible} of ${total} sources`
  }

  // `/` is the search key on every page here that has a lot of rows. Never
  // steals a keystroke meant for a field somebody is already typing in.
  hotkey(event) {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
    const active = document.activeElement
    if (active && (active.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(active.tagName))) return
    if (!this.hasInputTarget) return

    event.preventDefault()
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  clear() {
    if (!this.hasInputTarget) return
    this.inputTarget.value = ""
    this.filter()
  }
}
