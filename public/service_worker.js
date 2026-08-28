// Browser push (D22): payloads carry a title and a count/titles summary
// only — details stay in the app.
self.addEventListener("push", (event) => {
  const data = event.data ? event.data.json() : {};
  event.waitUntil(
    self.registration.showNotification(data.title || "Assistant", {
      body: data.body || "",
      icon: "/icon.png",
      // The decision link (D-decision-links), carried through to the click
      // handler below so a tap lands on the things to decide rather than on
      // the dashboard.
      data: { url: data.url || "/" }
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  // Same-origin only: the URL came from our own payload, but a push handler
  // is the wrong place to trust that without checking.
  let target = "/";
  try {
    const url = new URL(event.notification.data?.url || "/", self.location.origin);
    if (url.origin === self.location.origin) target = url.href;
  } catch (error) {
    target = "/";
  }
  event.waitUntil(clients.openWindow(target));
});
