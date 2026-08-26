import { Controller } from "@hotwired/stimulus"

// Instant, styled tooltips for navigation and action triggers.
//
// The bubble carries the trigger's name and, when there is one, a `detail`
// string: what is waiting behind that door right now (a date, a count, a
// pile). Deliberately not a description — a tooltip that restates the label
// is a no-op beside a labelled row and a bare label beside a collapsed one.
//
// The title is `aria-hidden` inside the bubble because the trigger's own
// accessible name already says it; the bubble is wired up as the trigger's
// description instead, so a screen reader hears the state and not the name
// twice.
let tooltipSequence = 0

export default class extends Controller {
  static values = {
    title: String,
    detail: String,
    badge: String,
    placement: { type: String, default: "right" }
  }

  connect() {
    this.show = this.show.bind(this)
    this.hide = this.hide.bind(this)
    this.onKeyDown = this.onKeyDown.bind(this)

    this.element.addEventListener("mouseenter", this.show)
    this.element.addEventListener("mouseleave", this.hide)
    this.element.addEventListener("focusin", this.show)
    this.element.addEventListener("focusout", this.hide)
    window.addEventListener("keydown", this.onKeyDown)
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.show)
    this.element.removeEventListener("mouseleave", this.hide)
    this.element.removeEventListener("focusin", this.show)
    this.element.removeEventListener("focusout", this.hide)
    window.removeEventListener("keydown", this.onKeyDown)
    this.removeTooltip()
  }

  show() {
    if (this.tooltipEl) return

    const title = this.titleValue || this.element.getAttribute("aria-label") || ""
    if (!title) return

    const tooltip = document.createElement("div")
    tooltip.className = "tooltip-bubble fixed z-50 pointer-events-none opacity-0 scale-95 transition-all duration-100 ease-out"
    tooltip.setAttribute("role", "tooltip")
    tooltip.id = `tooltip-${++tooltipSequence}`

    let innerHTML = `<div class="tooltip-card flex flex-col gap-1 rounded-xl bg-stone-900 px-3 py-2 text-stone-100 shadow-xl border border-stone-700/60 max-w-xs">`

    innerHTML += `<span class="font-semibold text-xs text-stone-100 tracking-wide min-w-[120px]" aria-hidden="true">${this.escapeHtml(title)}</span>`

    // The state row: a chip for something that wants doing, then the line.
    if (this.detailValue || this.badgeValue) {
      innerHTML += `<div class="flex items-center gap-2 pt-0.5 text-[11px] leading-tight text-stone-400">`
      if (this.badgeValue) {
        innerHTML += `<span class="inline-flex shrink-0 items-center rounded-full bg-primary-500/20 px-1.5 py-0.5 text-[10px] font-medium text-primary-300 border border-primary-500/30">${this.escapeHtml(this.badgeValue)}</span>`
      }
      if (this.detailValue) {
        innerHTML += `<span>${this.escapeHtml(this.detailValue)}</span>`
      }
      innerHTML += `</div>`
    }

    // Caret arrow (pointing left for placement: right)
    innerHTML += `<div class="tooltip-arrow absolute -left-1.5 top-1/2 -mt-1.5 size-3 rotate-45 bg-stone-900 border-l border-b border-stone-700/60"></div>`
    innerHTML += `</div>`

    tooltip.innerHTML = innerHTML
    document.body.appendChild(tooltip)
    this.tooltipEl = tooltip
    this.element.setAttribute("aria-describedby", tooltip.id)

    this.positionTooltip()

    // Trigger micro transition immediately in next frame
    requestAnimationFrame(() => {
      if (this.tooltipEl) {
        this.tooltipEl.classList.remove("opacity-0", "scale-95")
        this.tooltipEl.classList.add("opacity-100", "scale-100")
      }
    })
  }

  hide() {
    this.removeTooltip()
  }

  onKeyDown(event) {
    if (event.key === "Escape") {
      this.hide()
    }
  }

  positionTooltip() {
    if (!this.tooltipEl) return

    const rect = this.element.getBoundingClientRect()
    const tooltipRect = this.tooltipEl.getBoundingClientRect()

    // Default right side placement
    let left = rect.right + 12
    let top = rect.top + (rect.height / 2) - (tooltipRect.height / 2)

    // Clamp top position so it doesn't go outside viewport
    const padding = 8
    if (top < padding) top = padding
    if (top + tooltipRect.height > window.innerHeight - padding) {
      top = window.innerHeight - padding - tooltipRect.height
    }

    this.tooltipEl.style.left = `${left}px`
    this.tooltipEl.style.top = `${top}px`

    // Position arrow relative to the trigger link
    const arrow = this.tooltipEl.querySelector(".tooltip-arrow")
    if (arrow) {
      const triggerCenterY = rect.top + (rect.height / 2)
      const arrowTop = Math.max(10, Math.min(tooltipRect.height - 14, triggerCenterY - top))
      arrow.style.top = `${arrowTop}px`
    }
  }

  removeTooltip() {
    if (this.tooltipEl) {
      this.element.removeAttribute("aria-describedby")
      this.tooltipEl.remove()
      this.tooltipEl = null
    }
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.innerText = str
    return div.innerHTML
  }
}
