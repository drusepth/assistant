import { Controller } from "@hotwired/stimulus"

// Subscribes this browser to Web Push against the instance's own VAPID
// key and stores the subscription as a notification channel.
export default class extends Controller {
  static values = { vapidKey: String }
  static targets = ["status"]

  async subscribe() {
    try {
      if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
        return this.report("This browser doesn't support push notifications.")
      }
      const registration = await navigator.serviceWorker.register("/service_worker.js")
      const permission = await Notification.requestPermission()
      if (permission !== "granted") return this.report("Notifications were blocked — allow them in your browser settings.")

      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this.urlBase64ToUint8Array(this.vapidKeyValue)
      })

      const response = await fetch("/notification_channels", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ kind: "web_push", subscription: subscription.toJSON() })
      })
      if (!response.ok) throw new Error("save failed")
      window.location.reload()
    } catch {
      this.report("Couldn't enable push — note it needs HTTPS (or localhost).")
    }
  }

  report(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    const raw = window.atob(base64)
    return Uint8Array.from([...raw].map((char) => char.charCodeAt(0)))
  }
}
