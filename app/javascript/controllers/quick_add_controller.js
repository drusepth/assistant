import { Controller } from "@hotwired/stimulus"

// Quick-add dropdowns (Ui::QuickAddComponent): a + button opens its capture
// form in a panel anchored beneath it instead of navigating to the new-item
// page. Every component carries its own instance, so the one-open-at-a-time
// rule is kept across instances with a window event: opening a panel
// announces itself, and every other instance closes. Escape, Cancel, or
// clicking outside closes too.
export default class extends Controller {
  static targets = ["panel", "button"]

  toggle(event) {
    const name = event.params.name
    const panel = this.panelTargets.find(p => p.dataset.name === name)
    if (!panel) return

    const opening = panel.classList.contains("hidden")
    this.closeAll()
    if (opening) {
      this.dispatch("opened", { target: window, prefix: "quick-add", detail: { controller: this } })
      panel.classList.remove("hidden")
      this.buttonTargets
        .find(b => b.dataset.quickAddNameParam === name)
        ?.setAttribute("aria-expanded", "true")
      panel.querySelector("input:not([type=hidden]), textarea")?.focus()
    }
  }

  // "Full form" takes what's already typed along with it: the first field of
  // the panel's form (a title, or a note's body) rides on the link's query
  // string, which the new-item page reads as a prefill.
  carryOver(event) {
    const link = event.currentTarget
    const field = link.closest("[data-quick-add-target=panel]")
      ?.querySelector("form input[type=text], form textarea")
    const key = field?.name.match(/\[(\w+)\]$/)?.[1]
    if (!key || !field.value.trim()) return

    const url = new URL(link.href, window.location.origin)
    url.searchParams.set(key, field.value)
    link.href = url.toString()
  }

  closeOthers(event) {
    if (event.detail?.controller !== this) this.closeAll()
  }

  closeAll() {
    this.panelTargets.forEach(p => p.classList.add("hidden"))
    this.buttonTargets.forEach(b => b.setAttribute("aria-expanded", "false"))
  }

  clickOutside(event) {
    const inside = [...this.panelTargets, ...this.buttonTargets].some(el => el.contains(event.target))
    if (!inside) this.closeAll()
  }
}
