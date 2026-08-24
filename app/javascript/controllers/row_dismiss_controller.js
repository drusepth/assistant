import { Controller } from "@hotwired/stimulus"

// The send-off for a row whose own button takes it off the list it is in —
// Today and Tomorrow on a task row on the Today screen.
//
// The write is an ordinary `button_to`: it PATCHes, the server redirects
// back, and the row is simply *absent* from the page that comes back. That
// reads as the app swallowing the tap: nothing acknowledges the press, and
// the row nearest your thumb blinks out with no sign of where it went.
//
// So this controller does two things, and neither of them is the write. It
// marks the side you picked and slides the row out; and it holds Turbo's
// re-render until that has played, by pausing `turbo:before-render` (which
// Turbo lets a listener do, and resumes when we say). The request is in
// flight the whole time, so on any real network the animation finishes
// before the response lands and costs nothing.
//
// The motion itself is CSS (`.row-leaving` in the Tailwind input) — this
// only decides which side won and when the row is done moving.
//
// Two things must never happen: the page must not sit frozen mid-visit
// because an animation didn't end, and a failed write must not leave a
// phantom hole where the row was. Hence the safety timer and the reset on
// an unsuccessful submit.
const SAFETY_MS = 700

export default class extends Controller {
  disconnect() {
    clearTimeout(this.safety)
    // Normally the hold has already taken itself off by now — it runs, and
    // *then* the render that disconnects this happens. This is for the row
    // that leaves the page some other way.
    if (this.onBeforeRender) document.removeEventListener("turbo:before-render", this.onBeforeRender)
  }

  leave(event) {
    const button = event.submitter
    // Not our pair of buttons (the complete checkbox is a form on this row
    // too), or a second tap on a row already on its way out.
    if (!button?.dataset.rowDismissDirection || this.leaving) return

    this.leaving = true
    this.hold(this.animate(button))

    // A 4xx/5xx or a dead network renders nothing, so the row would stay
    // collapsed and invisible over a task that is still there.
    this.element.addEventListener("turbo:submit-end", (submit) => {
      if (!submit.detail.success) this.reset()
    }, { once: true })
  }

  // Returns a promise that settles when the row has finished collapsing.
  animate(button) {
    button.classList.add("btn-chosen")
    this.element.classList.add("row-leaving", `row-leaving-${button.dataset.rowDismissDirection}`)
    // `height: auto` has nothing to transition from, so the row's own
    // height is measured and pinned before it is taken to zero.
    this.element.style.height = `${this.element.offsetHeight}px`

    const settled = new Promise((resolve) => {
      const ended = (transition) => {
        if (transition.target !== this.element || transition.propertyName !== "height") return
        this.element.removeEventListener("transitionend", ended)
        resolve()
      }
      this.element.addEventListener("transitionend", ended)
    })

    // A frame between the two states, or the browser has no start value to
    // interpolate from and jumps straight to the end.
    //
    // The padding goes with the height because the box is `border-box`: a
    // `height: 0` row still stands `py-3` tall — 24 points of nothing,
    // which is most of the gap the collapse was supposed to close.
    requestAnimationFrame(() => {
      this.element.classList.add("row-gone")
      this.element.style.height = "0px"
      this.element.style.paddingBlock = "0px"
    })

    return settled
  }

  // Turbo fires `turbo:before-render` for the visit the button kicked off,
  // and waits on the promise it hands back if a listener prevents the
  // default. One shot: the listener takes itself off on the first render,
  // so a row that has left never holds up a page the user navigates to
  // afterwards.
  hold(settled) {
    this.onBeforeRender = (render) => {
      document.removeEventListener("turbo:before-render", this.onBeforeRender)
      render.preventDefault()

      let resumed = false
      const resume = () => {
        if (resumed) return
        resumed = true
        clearTimeout(this.safety)
        // The app morphs on redirect-to-self, and morph matches these rows
        // by position rather than id — an inline height left behind here
        // would land on whichever row moves up into this one's place. The
        // reset runs in the same task as `resume()`, so nothing paints
        // between the two.
        this.reset()
        render.detail.resume()
      }

      this.safety = setTimeout(resume, SAFETY_MS)
      settled.then(resume)
    }

    document.addEventListener("turbo:before-render", this.onBeforeRender)
  }

  reset() {
    this.element.classList.remove("row-leaving", "row-leaving-now", "row-leaving-later", "row-gone")
    this.element.style.height = ""
    this.element.style.paddingBlock = ""
    this.element.querySelector(".btn-chosen")?.classList.remove("btn-chosen")
    this.leaving = false
  }
}
