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
      const properties = ["name", "tel", "email", "address", "icon"].filter(p => available.includes(p))
      picked = await navigator.contacts.select(properties, { multiple: true })
    } catch {
      return // picker dismissed, or not allowed right now (e.g. another picker open)
    }
    if (!picked || picked.length === 0) return

    this.fieldTarget.value = JSON.stringify(await Promise.all(picked.map(contact => this.serialize(contact))))
    this.formTarget.requestSubmit()
  }

  // ContactAddress properties live on the prototype, so JSON.stringify would
  // drop them — copy everything into plain objects explicitly.
  async serialize(contact) {
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
      })),
      icon: await this.icon(contact)
    }
  }

  // Contact photos come over as Blobs, which JSON.stringify would drop: the
  // first one becomes a data: URL the import attaches as the contact's
  // photo. Anything large is skipped — an address book of full-size photos
  // would post megabytes through a hidden field, and the app only ever
  // renders a 200px square anyway.
  async icon(contact) {
    const blob = (contact.icon || [])[0]
    if (!blob || blob.size === 0 || blob.size > 2 * 1024 * 1024) return []

    const dataUrl = await new Promise(resolve => {
      const reader = new FileReader()
      reader.onload = () => resolve(reader.result)
      reader.onerror = () => resolve(null)
      reader.readAsDataURL(blob)
    })
    return dataUrl ? [dataUrl] : []
  }
}
