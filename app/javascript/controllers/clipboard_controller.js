import { Controller } from "@hotwired/stimulus"

// Copies the source input's value; briefly confirms on the button.
export default class extends Controller {
  static targets = ["source", "button"]

  copy() {
    navigator.clipboard.writeText(this.sourceTarget.value)
    const original = this.buttonTarget.textContent
    this.buttonTarget.textContent = "Copied!"
    setTimeout(() => { this.buttonTarget.textContent = original }, 1500)
  }
}
