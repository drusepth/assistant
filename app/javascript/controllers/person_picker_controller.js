import { Controller } from "@hotwired/stimulus"

// The person picker (D-person-picker): a combobox over the address book.
// Typing asks the server for up to eight matches (People::MatchesController,
// which renders the option rows) plus an "Add … as a new contact" row when
// the name is nobody's yet. Picking a person fills the hidden person_id and
// submits; picking the new row, or pressing Enter without picking anything,
// submits the typed name and the server makes (or finds) the contact.
//
// Nothing is highlighted until you arrow to it, unless the typed name is
// exactly someone's: Enter on "Ann" must not quietly add "Anna Lee".
//
// Without this controller the field is a plain name input that still works.
export default class extends Controller {
  static targets = ["input", "id", "list"]
  static values = { url: String }

  activeIndex = -1

  connect() {
    // A picker folded inside a <details> ("Add someone" on a card) is
    // opened in order to type, so opening it focuses the field.
    this.details = this.element.closest("details")
    this.onToggle = () => { if (this.details.open) this.inputTarget.focus() }
    this.details?.addEventListener("toggle", this.onToggle)
  }

  disconnect() {
    this.details?.removeEventListener("toggle", this.onToggle)
    this.abort?.abort()
    clearTimeout(this.timer)
  }

  search(event) {
    // A pick belongs to the text it was made from; editing the text undoes it.
    if (event.type === "input") this.idTarget.value = ""
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetch(), 120)
  }

  async fetch() {
    const query = this.inputTarget.value.trim()
    if (!query) return this.close()

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

    this.listTarget.innerHTML = html
    this.options.forEach((option, index) => { option.id = `${this.listTarget.id}-${index}` })
    if (this.options.length === 0) return this.close()

    this.open()
    const exact = this.options.find(option => option.dataset.personId && option.dataset.name.toLowerCase() === query.toLowerCase())
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
        }
        break
      case "Escape":
        if (expanded) {
          event.preventDefault()
          this.close()
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
    this.idTarget.value = option.dataset.personId || ""
    this.inputTarget.value = option.dataset.name
    this.close()
    this.inputTarget.form?.requestSubmit()
  }

  close() {
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
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
}
