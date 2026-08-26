import { Controller } from "@hotwired/stimulus"

// The Address Book's instant filter (D-address-book-directory).
//
// The search field is a real GET form and works with this controller absent:
// type, press Enter, the server searches every field including notes. What
// this adds is the part that decides whether the page *feels* like an
// address book — the list narrowing on the keystroke, with no round trip and
// no flash of a re-rendered page. Every row already carries everything a
// query is matched against in `data-directory-haystack`, so filtering four
// hundred contacts is four hundred `String.includes` calls: microseconds.
//
// Three things narrow together, and they have to stay in step or the page
// lies: the rows, the A–Z headings above them (a heading with nothing under
// it is a promise the list doesn't keep), and the jump rail, whose letters
// grey out as they empty so it never scrolls you somewhere blank.
export default class extends Controller {
  static targets = ["input", "row", "group", "rail", "empty", "count"]
  static values = { roster: Number }

  connect() {
    // A morph, a bfcache restore, or a browser that kept the field's text
    // can all land us here with a query already typed and every row shown.
    this.filter()
  }

  filter() {
    const query = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    this.matches = []

    this.rowTargets.forEach((row) => {
      const match = query === "" || (row.dataset.directoryHaystack || "").includes(query)
      // Display rather than the `hidden` attribute: these rows carry a
      // `flex` class, which outranks the user-agent's `[hidden]` rule and
      // would leave every "hidden" row on screen.
      row.style.display = match ? "" : "none"
      if (match) this.matches.push(row)
    })
    const visible = this.matches.length

    const live = new Set()
    this.groupTargets.forEach((group) => {
      const shown = Array.from(group.querySelectorAll("[data-directory-target~='row']"))
        .some((row) => row.style.display !== "none")
      group.style.display = shown ? "" : "none"
      if (shown) live.add(group.dataset.directoryLetter)
    })

    this.railTargets.forEach((letter) => {
      // Only letters that were rendered in the first place are here, so an
      // empty one is empty *because of the query* — greying it is honest.
      letter.classList.toggle("opacity-25", !live.has(letter.dataset.directoryLetter))
      letter.classList.toggle("pointer-events-none", !live.has(letter.dataset.directoryLetter))
    })

    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", visible > 0)
    if (this.hasCountTarget) this.countTarget.textContent = this.phrase(visible)
  }

  // Mirrors `PeopleHelper#directory_count_phrase`, so the number doesn't
  // change shape the moment you touch the keyboard.
  phrase(visible) {
    const roster = this.hasRosterValue ? this.rosterValue : visible
    const noun = roster === 1 ? "person" : "people"
    return visible === roster ? `${roster} ${noun}` : `${visible} of ${roster} ${noun}`
  }

  // `/` is the search key everywhere that has a lot of rows and expects you
  // to know where you're going. Never steals a keystroke you meant for a
  // field you're already typing in.
  hotkey(event) {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
    const active = document.activeElement
    if (active && (active.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(active.tagName))) return
    if (!this.hasInputTarget) return

    event.preventDefault()
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  // Enter with exactly one name left is unambiguous: that is the person you
  // were looking for, so open them rather than round-tripping the same
  // search to the server to be told what the screen already shows. Any other
  // count submits the form, which searches fields the instant filter can't
  // (a long note) and gives you a URL you can keep.
  open(event) {
    if (!this.matches || this.matches.length !== 1) return

    // The name, not the avatar beside it: that one is a decorative
    // duplicate and carries aria-hidden.
    const link = this.matches[0].querySelector('a[href]:not([aria-hidden])')
    if (!link) return

    event.preventDefault()
    link.click()
  }

  clear() {
    if (!this.hasInputTarget) return
    this.inputTarget.value = ""
    this.filter()
  }
}
