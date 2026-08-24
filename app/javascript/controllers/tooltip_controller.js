import { Controller } from "@hotwired/stimulus"

// Instant, styled JS tooltips for navigation and action triggers.
// Renders rich floating UI with title, subtext, badges, and shortcut key hints.
export default class extends Controller {
  static values = {
    title: String,
    subtitle: String,
    badge: String,
    shortcut: String,
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

    let innerHTML = `<div class="tooltip-card flex flex-col gap-1 rounded-xl bg-stone-900 px-3 py-2 text-stone-100 shadow-xl border border-stone-700/60 max-w-xs">`
    
    // Top row: Title + optional Kbd shortcut
    innerHTML += `<div class="flex items-center justify-between gap-3 min-w-[120px]">`
    innerHTML += `<span class="font-semibold text-xs text-stone-100 tracking-wide">${this.escapeHtml(title)}</span>`
    if (this.shortcutValue) {
      innerHTML += `<kbd class="inline-flex items-center justify-center rounded px-1.5 py-0.5 font-mono text-[10px] font-medium bg-stone-800 text-stone-300 border border-stone-700/70 shadow-xs">${this.escapeHtml(this.shortcutValue)}</kbd>`
    }
    innerHTML += `</div>`

    // Subtitle / Badge row if present
    if (this.subtitleValue || this.badgeValue) {
      innerHTML += `<div class="flex items-center gap-2 pt-0.5 text-[11px] leading-tight text-stone-400">`
      if (this.badgeValue) {
        innerHTML += `<span class="inline-flex items-center rounded-full bg-primary-500/20 px-1.5 py-0.5 text-[10px] font-medium text-primary-300 border border-primary-500/30">${this.escapeHtml(this.badgeValue)}</span>`
      }
      if (this.subtitleValue) {
        innerHTML += `<span class="truncate">${this.escapeHtml(this.subtitleValue)}</span>`
      }
      innerHTML += `</div>`
    }

    // Caret arrow (pointing left for placement: right)
    innerHTML += `<div class="tooltip-arrow absolute -left-1.5 top-1/2 -mt-1.5 size-3 rotate-45 bg-stone-900 border-l border-b border-stone-700/60"></div>`
    innerHTML += `</div>`

    tooltip.innerHTML = innerHTML
    document.body.appendChild(tooltip)
    this.tooltipEl = tooltip

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
