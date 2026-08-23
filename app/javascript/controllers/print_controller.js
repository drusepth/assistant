import { Controller } from "@hotwired/stimulus"

// The print dialog, from a button rather than an inline handler (the CSP
// blocks those). A recipe is one of the few pages people genuinely print,
// and @media print in the stylesheet is what makes the page worth printing.
export default class extends Controller {
  now() {
    window.print()
  }
}
