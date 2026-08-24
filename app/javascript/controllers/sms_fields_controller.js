import { Controller } from "@hotwired/stimulus"

// Shows only the fields the selected SMS provider needs. Mirrors
// NotificationChannel::SMS_PROVIDERS — a modem needs a directory, a
// carrier needs credentials, and nobody needs to look at both.
export default class extends Controller {
  static targets = ["select", "fields"]

  connect() {
    this.refresh()
  }

  refresh() {
    const provider = this.selectTarget.value
    this.fieldsTargets.forEach((fields) => {
      fields.hidden = fields.dataset.smsProvider !== provider
    })
  }
}
