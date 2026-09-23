import { Controller } from "@hotwired/stimulus"

// The Breed box's photo helper: sends a chosen photo (or an upload) and the
// species picked on the form, renders the suggestions the server streams
// back, and fills the box when one is tapped. It never submits the pet form.
export default class extends Controller {
  static targets = ["input", "file", "panel"]
  static values = { url: String }

  guess({ params, currentTarget }) {
    this.mark(currentTarget)
    const body = new FormData()
    if (params.photoId) body.append("photo_id", params.photoId)
    if (params.petId) body.append("pet_id", params.petId)
    this.send(body)
  }

  upload() {
    const file = this.fileTarget.files[0]
    if (!file) return

    this.mark(null)
    const body = new FormData()
    body.append("photo", file)
    this.send(body)
    this.fileTarget.value = ""
  }

  use({ params }) {
    this.inputTarget.value = params.name
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.inputTarget.focus()
    this.panelTarget.open = false
  }

  send(body) {
    const species = this.element.closest("form")?.querySelector("[name='pet[species]']")
    if (species) body.append("species", species.value)
    this.result.innerHTML = `<p class="text-soft">Looking…</p>`

    fetch(this.urlValue, {
      method: "POST",
      body,
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
      },
      credentials: "same-origin"
    })
      .then(response => {
        if (!response.ok) throw new Error(response.statusText)
        return response.text()
      })
      .then(html => window.Turbo.renderStreamMessage(html))
      .catch(() => {
        this.result.innerHTML = `<p class="field-error">Couldn't reach the app — try again, or type the breed in.</p>`
      })
  }

  // The tapped photo wears a ring, so it's clear which one is being read.
  mark(button) {
    this.element.querySelectorAll("[data-breed-guess-photo-id-param], [data-breed-guess-pet-id-param]")
      .forEach(el => el.classList.toggle("ring-2", el === button))
  }

  get result() {
    return this.element.querySelector("#breed_guess_result")
  }
}
