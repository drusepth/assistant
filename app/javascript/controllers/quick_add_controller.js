import { Controller } from "@hotwired/stimulus"

// Header quick-add dropdowns (Ui::QuickAddComponent): each + button in the
// page header opens its capture form in a panel anchored beneath it instead
// of navigating to the new-item page. One panel open at a time; Escape,
// Cancel, or clicking outside closes.
export default class extends Controller {
  static targets = ["panel", "button"]

  toggle(event) {
    const name = event.params.name
    const panel = this.panelTargets.find(p => p.dataset.name === name)
    if (!panel) return

    const opening = panel.classList.contains("hidden")
    this.closeAll()
    if (opening) {
      panel.classList.remove("hidden")
      this.buttonTargets
        .find(b => b.dataset.quickAddNameParam === name)
        ?.setAttribute("aria-expanded", "true")
      panel.querySelector("input:not([type=hidden]), textarea")?.focus()
    }
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
