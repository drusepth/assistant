import { Controller } from "@hotwired/stimulus"

// The in-store list's taps (docs/FOOD_PLAN.md §4). A tap moves the row
// *now* — into the basket or back out — and the write follows. In a
// bad-signal aisle the write may not make it: then it waits in a queue,
// a quiet chip says how many are waiting, and the queue drains the moment
// the phone is back online. The queue lives in memory, so a closed tab
// loses it (Q-kitchen-offline, resolved: build more only if stores prove
// it's needed).
//
// Enter in the quick-add box adds; Shift+Enter is a new line, for the
// person typing several things at once. A paste of many lines just works.
export default class extends Controller {
  static targets = ["open", "basket", "pending", "input"]

  connect() {
    this.queue = []
    this.flush = this.flush.bind(this)
    window.addEventListener("online", this.flush)
  }

  disconnect() {
    window.removeEventListener("online", this.flush)
  }

  toggle(event) {
    event.preventDefault()
    const button = event.currentTarget
    const row = button.closest("[data-item-row]")
    const checking = row.dataset.checked !== "true"

    row.dataset.checked = checking ? "true" : "false"
    if (checking) this.basketTarget.prepend(row)
    else this.aisleFor(row).append(row)
    if (this.hasBasketTarget) this.basketTarget.closest("[data-basket]")?.classList.toggle("hidden", this.basketTarget.children.length === 0)

    this.send(checking ? button.dataset.checkUrl : button.dataset.uncheckUrl)
  }

  // Back to its aisle, or to the last group when its aisle has emptied.
  aisleFor(row) {
    const groups = [...this.openTarget.querySelectorAll("[data-aisle-group]")]
    return groups.find((group) => group.dataset.aisleGroup === (row.dataset.aisle || "")) || groups[groups.length - 1]
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    if (this.inputTarget.value.trim() !== "") this.inputTarget.form.requestSubmit()
  }

  async send(url) {
    try {
      const response = await fetch(url, {
        method: "PATCH",
        headers: { "X-CSRF-Token": this.csrfToken, "X-Optimistic": "1" },
        credentials: "same-origin"
      })
      if (!response.ok && response.status >= 500) throw new Error(response.statusText)
    } catch {
      this.queue.push(url)
      this.showPending()
    }
  }

  async flush() {
    const waiting = this.queue
    this.queue = []
    this.showPending()
    for (const url of waiting) await this.send(url)
  }

  showPending() {
    if (!this.hasPendingTarget) return

    const count = this.queue.length
    this.pendingTarget.hidden = count === 0
    this.pendingTarget.textContent = `${count} change${count === 1 ? "" : "s"} waiting to sync`
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
