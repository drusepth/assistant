import { Controller } from "@hotwired/stimulus"

// Keyboard focus across a morph.
//
// Every list action in the app is a `button_to`: PATCH, `redirect_back`, and
// the page morphs back into place. Turbo disables the submitter while the
// request is in flight, and a disabled element is not focusable — so focus
// is already on `<body>` by `turbo:submit-start`, long before the morph runs
// and long before idiomorph's own focus restoration could do anything about
// it. The visible cost: tick a task off Today with the keyboard and you are
// returned to the top of the document, with the whole page to tab through
// again before you can reach the next one.
//
// So the submitter's id is remembered on the way out and focus is put back
// on the way in. This only works because rows and their buttons carry stable
// ids (D-row-identity) — without them there is nothing to look the element
// up by.
//
// Restricted to morph renders on purpose. A real navigation is a new page
// and belongs at its top; only a redirect back to the page you were already
// on should leave you where you were standing.
export default class extends Controller {
  remember(event) {
    this.wanted = event.detail?.formSubmission?.submitter?.id
  }

  restore(event) {
    const wanted = this.wanted
    this.wanted = null
    if (!wanted || event.detail?.renderMethod !== "morph") return

    // Gone is a legitimate answer: the row a button belonged to may be the
    // thing the button just removed from the list. Then there is nothing to
    // return to and body is the honest place to be.
    // `preventScroll`, because the element is already where the user is
    // looking and a scroll into view would move the page under them.
    document.getElementById(wanted)?.focus({ preventScroll: true })
  }
}
