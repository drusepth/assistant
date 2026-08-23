import { Controller } from "@hotwired/stimulus"

// Shows only the fields the selected AI provider needs. Mirrors
// ModelProfile::PROVIDERS: custom exposes base_url; router-style
// providers (Chroma Golem) hide the model name; per-provider hints and
// model suggestions follow the picker.
export default class extends Controller {
  static targets = ["select", "baseUrl", "model", "modelInput", "hint"]
  static values = { suggestions: Object }

  connect() {
    this.refresh()
  }

  refresh() {
    const provider = this.selectTarget.value
    this.baseUrlTarget.hidden = provider !== "custom"
    this.modelTarget.hidden = provider === "chroma_golem"

    this.suggestModel(provider)
    this.hintTargets.forEach((hint) => {
      hint.hidden = hint.dataset.provider !== provider
    })
  }

  // Swap one provider's suggested model for another's, but never overwrite a
  // name the household typed themselves — a value we didn't suggest is theirs.
  suggestModel(provider) {
    if (!this.hasModelInputTarget) return

    const suggestion = this.suggestionsValue[provider]
    if (!suggestion) return

    const current = this.modelInputTarget.value.trim()
    const ours = current === "" || Object.values(this.suggestionsValue).includes(current)
    if (ours) this.modelInputTarget.value = suggestion
  }
}
