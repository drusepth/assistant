import { Controller } from "@hotwired/stimulus"

// Shows only the fields the selected AI provider needs. Mirrors
// ModelProfile::PROVIDERS: custom exposes base_url; router-style
// providers (Chroma Golem) hide the model name.
export default class extends Controller {
  static targets = ["select", "baseUrl", "model"]

  connect() {
    this.refresh()
  }

  refresh() {
    const provider = this.selectTarget.value
    this.baseUrlTarget.hidden = provider !== "custom"
    this.modelTarget.hidden = provider === "chroma_golem"
  }
}
