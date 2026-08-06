import { Controller } from "@hotwired/stimulus"

// Copies the source input's value — or the text value, for content that has
// no input to live in — and briefly confirms on the button.
export default class extends Controller {
  static targets = ["source", "button"]
  static values = { text: String }

  copy() {
    const text = this.hasSourceTarget ? this.sourceTarget.value : this.textValue
    navigator.clipboard.writeText(text)
    const original = this.buttonTarget.textContent
    this.buttonTarget.textContent = "Copied!"
    setTimeout(() => { this.buttonTarget.textContent = original }, 1500)
  }
}
