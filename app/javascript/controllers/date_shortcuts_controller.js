import { Controller } from "@hotwired/stimulus"

// Quick-pick chips under a date input: one click fills the field. The dates
// themselves are computed server-side and carried in each chip's date param.
export default class extends Controller {
  static targets = ["input"]

  set(event) {
    this.inputTarget.value = event.params.date
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
