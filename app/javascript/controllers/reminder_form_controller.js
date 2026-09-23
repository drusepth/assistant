import { Controller } from "@hotwired/stimulus"

// The Repeat picker (D-standing-reminders), on a task's form and on an
// event's reminder. A weekly repeat unfolds the weekday chips and
// pre-checks the picked date's weekday; any repeat unfolds the "until"
// targets, folds the "once" ones, and relabels the date ("Due" becomes
// "Starting" on a task); the monthly option names the picked day ("Every
// month on the 19th"). All of it is presentation: the server composes the rule from
// whatever the form sends, so with JavaScript off the same form still works
// — the chips are simply always visible and the default day is the date's.
const CODES = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
const WEEKLY = ["weekly", "biweekly"]

export default class extends Controller {
  static targets = ["date", "repeat", "days", "day", "until", "once"]
  static values = { onceLabel: { type: String, default: "On" }, repeatLabel: { type: String, default: "Starting" } }

  connect() {
    this.autoCode = null
    this.sync()
    this.relabel()
  }

  repeatChanged() {
    this.sync()
    this.relabel()
  }

  dateChanged() {
    // Follow the date only while the chips still say what we set for them;
    // a day the user chose by hand is theirs.
    const checked = this.checkedCodes()
    if (this.weekly && checked.length <= 1 && (checked.length === 0 || checked[0] === this.autoCode)) {
      this.dayTargets.forEach((day) => { day.checked = false })
      this.checkDateWeekday()
    }
    this.relabel()
  }

  get weekly() {
    return WEEKLY.includes(this.repeatTarget.value)
  }

  get repeating() {
    return this.repeatTarget.value !== "none"
  }

  sync() {
    this.daysTarget.hidden = !this.weekly
    // Every target that only matters on a repeat, and every one that only
    // matters without one.
    this.untilTargets.forEach((target) => { target.hidden = !this.repeating })
    this.onceTargets.forEach((target) => { target.hidden = this.repeating })
    if (this.weekly && this.checkedCodes().length === 0) this.checkDateWeekday()
  }

  checkDateWeekday() {
    const code = this.dateCode()
    const day = this.dayTargets.find((target) => target.value === code)
    if (!day) return
    day.checked = true
    this.autoCode = code
  }

  checkedCodes() {
    return this.dayTargets.filter((target) => target.checked).map((target) => target.value)
  }

  // The input's value is a plain calendar date; read it as one, never
  // through Date.parse, which would take it as UTC midnight and hand back
  // yesterday's weekday for anyone west of Greenwich.
  dateParts() {
    if (!this.hasDateTarget) return null
    const [year, month, day] = this.dateTarget.value.split("-").map(Number)
    return year && month && day ? { year, month, day } : null
  }

  dateCode() {
    const parts = this.dateParts()
    return parts ? CODES[new Date(parts.year, parts.month - 1, parts.day).getDay()] : null
  }

  relabel() {
    const monthly = this.repeatTarget.querySelector('option[value="monthly"]')
    const parts = this.dateParts()
    if (monthly) monthly.textContent = parts ? `Every month on the ${ordinal(parts.day)}` : "Every month"

    if (!this.hasDateTarget) return
    const label = this.element.querySelector(`label[for="${this.dateTarget.id}"]`)
    if (label) label.textContent = this.repeating ? this.repeatLabelValue : this.onceLabelValue
  }
}

function ordinal(n) {
  const rest = n % 100
  if (rest >= 11 && rest <= 13) return `${n}th`
  return `${n}${["th", "st", "nd", "rd"][n % 10] || "th"}`
}
