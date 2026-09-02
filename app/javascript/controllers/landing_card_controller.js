import { Controller } from "@hotwired/stimulus"

// A landing card on the review page: unticking it fades its fields, so the
// eye can tell at a glance what will land. Nothing is disabled — an unticked
// card's edits are simply not read, which is what the server does too.
export default class extends Controller {
  static targets = ["keep", "fields"]

  connect() {
    this.toggle()
  }

  toggle() {
    const on = this.keepTarget.checked
    this.fieldsTarget.classList.toggle("opacity-40", !on)
    this.fieldsTarget.classList.toggle("pointer-events-none", !on)
  }
}
