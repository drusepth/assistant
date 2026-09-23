import { Controller } from "@hotwired/stimulus"

// The person picker (D-person-picker): a combobox over the address book.
// Typing asks the server for up to eight matches (People::MatchesController,
// which renders the option rows) plus an "Add …" row when the name is
// nobody's yet; focusing the empty field asks for a few suggestions instead
// (people you just added, who's in your photos, birthdays coming up).
// Picking a person fills the hidden person_id and submits; picking the new
// row, or pressing Enter without picking anything, submits the typed name
// and the server makes (or finds) the contact.
//
// Nothing is highlighted until you arrow to it, unless the typed name is
// exactly someone's: Enter on "Ann" must not quietly add "Anna Lee".
//
// A form answered in place (Turbo Streams) keeps this field on the page, so
// a successful submit clears it and keeps the cursor for the next name.
//
// On a phone the dropdown would open under the keyboard, so there the field
// becomes a full-screen sheet while it has focus: field and Cancel at the
// top, results filling the rest.
//
// Without this controller the field is a plain name input that still works.
export default class extends Controller {
  static targets = ["input", "id", "list"]
  static values = { url: String }

  activeIndex = -1

  connect() {
    this.form = this.inputTarget.form
    this.onSubmitEnd = event => {
      if (!event.detail.success) return
      // A keystroke's search still in flight would reopen the list over
      // the face that just landed.
      this.#cancelPending()
      this.inputTarget.value = ""
      this.idTarget.value = ""
      this.close()
      // Back in the field for the next name, but without reopening the
      // suggestions over the face that just landed — typing brings them.
      this.quiet = true
      this.inputTarget.focus({ preventScroll: true })
      this.quiet = false
    }
    this.form?.addEventListener("turbo:submit-end", this.onSubmitEnd)
    this.phone = window.matchMedia("(max-width: 639px)")
  }

  disconnect() {
    this.form?.removeEventListener("turbo:submit-end", this.onSubmitEnd)
    this.#cancelPending()
    this.#sheet(false)
  }

  focus() {
    if (this.phone.matches) this.#sheet(true)
    if (!this.quiet) this.fetch()
  }

  search(event) {
    // A pick belongs to the text it was made from; editing the text undoes it.
    if (event.type === "input") this.idTarget.value = ""
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetch(), 120)
  }

  async fetch() {
    const query = this.inputTarget.value.trim()

    this.abort?.abort()
    this.abort = new AbortController()
    const url = new URL(this.urlValue, window.location.href)
    url.searchParams.set("q", query)

    let html
    try {
      const response = await fetch(url, { signal: this.abort.signal, headers: { Accept: "text/html" } })
      if (!response.ok) return this.close()
      html = await response.text()
    } catch {
      return // superseded by a newer keystroke, or offline — the field still submits
    }
    if (this.inputTarget.value.trim() !== query) return
    if (document.activeElement !== this.inputTarget) return

    this.listTarget.innerHTML = html
    this.options.forEach((option, index) => { option.id = `${this.listTarget.id}-${index}` })
    if (this.options.length === 0) return this.close({ keepSheet: true })

    this.open()
    const exact = query && this.options.find(option => option.dataset.personId && option.dataset.name.toLowerCase() === query.toLowerCase())
    this.highlight(exact ? this.options.indexOf(exact) : -1)
  }

  navigate(event) {
    const expanded = !this.listTarget.hidden
    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp": {
        if (!expanded) return this.fetch()
        event.preventDefault()
        // Wraps through "nothing highlighted" (-1), so arrowing past the
        // ends gets you back to plain typing.
        const count = this.options.length
        let next = this.activeIndex + (event.key === "ArrowDown" ? 1 : -1)
        if (next >= count) next = -1
        if (next < -1) next = count - 1
        this.highlight(next)
        break
      }
      case "Enter":
        if (expanded && this.active) {
          event.preventDefault()
          this.choose(this.active)
        } else {
          this.#cancelPending() // the form submits the typed name as-is
          this.close({ keepSheet: true })
        }
        break
      case "Escape":
        if (expanded || this.sheetOpen) {
          event.preventDefault()
          this.dismiss()
        }
        break
    }
  }

  // mousedown, not click: a click lands after the input's blur has already
  // closed the list. preventDefault keeps the focus in the field.
  pick(event) {
    const option = event.target.closest("[role=option]")
    if (!option) return
    event.preventDefault()
    this.choose(option)
  }

  choose(option) {
    this.#cancelPending()
    this.idTarget.value = option.dataset.personId || ""
    this.inputTarget.value = option.dataset.name
    this.close()
    this.form?.requestSubmit()
  }

  // The sheet's Cancel, and Escape: out of the field altogether.
  dismiss() {
    this.close()
    this.inputTarget.blur()
  }

  blur() {
    this.close()
  }

  close({ keepSheet = false } = {}) {
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    if (!keepSheet && document.activeElement !== this.inputTarget) this.#sheet(false)
  }

  open() {
    this.listTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  highlight(index) {
    this.activeIndex = index
    this.options.forEach((option, i) => option.setAttribute("aria-selected", String(i === index)))
    if (this.active) {
      this.inputTarget.setAttribute("aria-activedescendant", this.active.id)
      this.active.scrollIntoView({ block: "nearest" })
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }

  get options() {
    return Array.from(this.listTarget.querySelectorAll("[role=option]"))
  }

  get active() {
    return this.options[this.activeIndex]
  }

  get sheetOpen() {
    return this.element.classList.contains("picker-sheet-open")
  }

  #cancelPending() {
    clearTimeout(this.timer)
    this.abort?.abort()
  }

  #sheet(on) {
    this.element.classList.toggle("picker-sheet-open", on)
    document.documentElement.classList.toggle("overflow-hidden", on)
  }
}
