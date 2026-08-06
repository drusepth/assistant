import { Controller } from "@hotwired/stimulus"

// Mobile path for contact import: the Contact Picker API (Chrome, Edge, and
// Samsung Internet on Android) opens the phone's own contacts picker, so
// nobody has to hunt down an export file. Picked contacts are serialized
// into the hidden field and posted through the same import pipeline as file
// uploads. The whole block stays hidden on browsers without the API.
export default class extends Controller {
  static targets = ["field", "form"]

  connect() {
    if ("contacts" in navigator && "select" in navigator.contacts) {
      this.element.classList.remove("hidden")
    }
  }

  async pick() {
    let picked
    try {
      const available = await navigator.contacts.getProperties()
      const properties = ["name", "tel", "email", "address"].filter(p => available.includes(p))
      picked = await navigator.contacts.select(properties, { multiple: true })
    } catch {
      return // picker dismissed, or not allowed right now (e.g. another picker open)
    }
    if (!picked || picked.length === 0) return

    this.fieldTarget.value = JSON.stringify(picked.map(contact => this.serialize(contact)))
    this.formTarget.requestSubmit()
  }

  // ContactAddress properties live on the prototype, so JSON.stringify would
  // drop them — copy everything into plain objects explicitly.
  serialize(contact) {
    return {
      name: contact.name,
      tel: contact.tel,
      email: contact.email,
      address: (contact.address || []).map(a => ({
        addressLine: a.addressLine,
        city: a.city,
        region: a.region,
        postalCode: a.postalCode,
        country: a.country
      }))
    }
  }
}
