// Browser push (D22): payloads carry a title and a count/titles summary
// only — details stay in the app.
self.addEventListener("push", (event) => {
  const data = event.data ? event.data.json() : {};
  event.waitUntil(
    self.registration.showNotification(data.title || "Assistant", {
      body: data.body || "",
      icon: "/icon.png"
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow("/"));
});
