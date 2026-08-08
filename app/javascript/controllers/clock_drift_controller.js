import { Controller } from "@hotwired/stimulus"

// TOTP codes are computed from the server's clock (PASSWORDS_PLAN §4.4). A
// home server whose NTP has drifted hands out codes that sites reject, and
// the failure looks like "the vault is broken" rather than "the box is
// wrong" — so say which it is. Only rendered where TOTP entries exist.
export default class extends Controller {
  static values = { serverTime: Number, tolerance: { type: Number, default: 30 } }

  connect() {
    const drift = Math.abs(Date.now() / 1000 - this.serverTimeValue)
    if (drift <= this.toleranceValue) return

    this.element.textContent =
      `This server's clock is off by about ${Math.round(drift)}s, so one-time codes may be rejected. ` +
      `Fix the time on the machine running this app (usually: enable NTP).`
    this.element.classList.remove("hidden")
  }
}
