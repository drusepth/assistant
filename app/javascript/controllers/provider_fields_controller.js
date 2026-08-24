import { Controller } from "@hotwired/stimulus"

// Shows only the fields the selected AI provider needs, and only the
// providers the household allows. Mirrors ModelProfile::PROVIDERS: custom
// exposes base_url; router-style providers (Chroma Golem) hide the model
// name; per-provider hints and model suggestions follow the picker; and
// unticking "Allow cloud LLMs" takes every :cloud preset out of the list.
export default class extends Controller {
  static targets = [
    "select", "baseUrl", "model", "modelInput", "hint",
    "allowCloud", "egressNote", "localNote"
  ]
  static values = {
    suggestions: Object,
    cloudProviders: Array,
    fallbackProvider: String
  }

  connect() {
    this.refresh()
  }

  refresh() {
    // Gate the list first: it can change which provider is selected, and
    // everything below reads that selection.
    this.gateCloudProviders()

    const provider = this.selectTarget.value
    this.baseUrlTarget.hidden = provider !== "custom"
    this.modelTarget.hidden = provider === "chroma_golem"

    this.suggestModel(provider)
    this.hintTargets.forEach((hint) => {
      hint.hidden = hint.dataset.provider !== provider
    })

    // Which "where does my text go" sentence is honest depends on whether
    // the endpoint is one we know or one the household typed.
    const known = this.cloudProvidersValue.includes(provider)
    if (this.hasEgressNoteTarget) this.egressNoteTarget.hidden = !known
    if (this.hasLocalNoteTarget) this.localNoteTarget.hidden = known
  }

  // Hidden *and* disabled: `hidden` on an <option> is ignored by some
  // browsers, and a disabled option can't be picked by keyboard either way.
  gateCloudProviders() {
    if (!this.hasAllowCloudTarget) return

    const allowed = this.allowCloudTarget.checked
    let selectionWasGated = false

    Array.from(this.selectTarget.options).forEach((option) => {
      if (!this.cloudProvidersValue.includes(option.value)) return

      option.hidden = !allowed
      option.disabled = !allowed
      if (!allowed && option.selected) selectionWasGated = true
    })

    // Leaving a now-hidden provider selected would submit a pair the model
    // rejects, so the form would bounce with an error the household can't
    // see the cause of. Move them somewhere valid instead.
    if (selectionWasGated) this.selectTarget.value = this.fallbackProviderValue
  }

  // Swap one provider's suggested model for another's, but never overwrite a
  // name the household typed themselves — a value we didn't suggest is ours
  // to replace, and anything else is theirs to keep. Moving to a provider we
  // have no suggestion for clears ours rather than leaving "gpt-4o-mini"
  // sitting above a box pointed at Ollama.
  suggestModel(provider) {
    if (!this.hasModelInputTarget) return

    const current = this.modelInputTarget.value.trim()
    const ours = current === "" || Object.values(this.suggestionsValue).includes(current)
    if (ours) this.modelInputTarget.value = this.suggestionsValue[provider] ?? ""
  }
}
