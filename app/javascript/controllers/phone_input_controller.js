import { Controller } from "@hotwired/stimulus"

// The phone mask every telephone field gets from ApplicationFormBuilder:
// you type digits, the box draws the "(503) 555-0142" around them. A leading
// "+" switches to an international number — the digits are kept as typed,
// since grouping them right takes a per-country table — and "+1" gets the
// North American mask after it. The server (PhoneNumber) is what actually
// decides the stored shape; this only makes typing it pleasant.
export default class extends Controller {
  // Set only on a box holding a number saved before the mask, which the
  // builder leaves submittable as-is; retyping it earns the check.
  static values = { pattern: String }

  connect() {
    this.previous = this.element.value
  }

  format(event) {
    const input = this.element
    if (this.hasPatternValue && !input.pattern) input.pattern = this.patternValue
    let value = input.value
    let caretDigits = digitsOf(value.slice(0, input.selectionStart ?? value.length)).length

    // Backspacing over a ")" or "-" would delete only what the mask puts
    // straight back, so the key would look dead — take the digit before it.
    if (event.inputType === "deleteContentBackward" && caretDigits > 0 &&
        digitsOf(value) === digitsOf(this.previous)) {
      const digits = digitsOf(value)
      value = (isInternational(value) ? "+" : "") + digits.slice(0, caretDigits - 1) + digits.slice(caretDigits)
      caretDigits -= 1
    }

    const { text, dropped } = mask(value)
    input.value = text
    if (document.activeElement === input) {
      const caret = caretAfter(text, Math.max(0, caretDigits - dropped))
      input.setSelectionRange(caret, caret)
    }
    this.previous = text
  }
}

const digitsOf = (value) => value.replace(/\D/g, "")
const isInternational = (value) => value.trimStart().startsWith("+")

// "(5", "(503) 5", "(503) 555-0" — drawn as far as the digits go, so the
// box never shows punctuation waiting for a digit that hasn't been typed.
function northAmerican(digits) {
  if (!digits) return ""
  if (digits.length <= 3) return `(${digits}`
  if (digits.length <= 6) return `(${digits.slice(0, 3)}) ${digits.slice(3)}`
  return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6, 10)}`
}

// The formatted text, plus how many typed digits it left out ahead of the
// caret (a leading "1" is the country code, not an area code).
function mask(value) {
  const digits = digitsOf(value)
  if (isInternational(value)) {
    const international = digits.slice(0, 15)
    if (international.startsWith("1") && international.length > 1) {
      return { text: `+1 ${northAmerican(international.slice(1, 11))}`, dropped: 0 }
    }
    return { text: `+${international}`, dropped: 0 }
  }
  if (digits.startsWith("1")) return { text: northAmerican(digits.slice(1, 11)), dropped: 1 }
  return { text: northAmerican(digits.slice(0, 10)), dropped: 0 }
}

// The caret goes back after the same number of digits it was after, so
// typing in the middle of a number doesn't throw it to the end.
function caretAfter(text, digitCount) {
  if (digitCount === 0) return text.startsWith("+") ? 1 : Math.min(1, text.length)
  let seen = 0
  for (let index = 0; index < text.length; index++) {
    if (/\d/.test(text[index]) && ++seen === digitCount) return index + 1
  }
  return text.length
}
