import { Controller } from "@hotwired/stimulus"

// One vaccine on the log form (D-pet-vaccinations). A typed good-until date
// is the certificate's and wins over a picked length, so once a date is in
// the length buttons step aside and say why, instead of letting both look
// chosen while one is silently ignored. The server applies the same rule
// with this controller absent; this only makes it visible.
export default class extends Controller {
  static targets = ["date", "durations", "hint", "note"]

  connect() {
    this.sync()
  }

  sync() {
    const dated = this.hasDateTarget && this.dateTarget.value !== ""
    if (this.hasDurationsTarget) this.durationsTarget.disabled = dated
    if (this.hasHintTarget) this.hintTarget.hidden = dated
    if (this.hasNoteTarget) this.noteTarget.hidden = !dated
  }
}
