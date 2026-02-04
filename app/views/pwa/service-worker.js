self.addEventListener("push", async (event) => {
  let payload = { title: "GeoMatch", body: "Nova notificação!", data: { path: "/" } };

  if (event.data) {
    try {
      payload = await event.data.json();
    } catch (e) {
      // Se não for JSON, trata como texto simples
      payload.body = event.data.text();
    }
  }

  const options = {
    body: payload.body,
    icon: '/icon.png', // Certifique-se de que este arquivo existe em /public
    badge: '/icon.png',
    data: payload.data
  };

  event.waitUntil(self.registration.showNotification(payload.title, options));
});

self.addEventListener("notificationclick", function(event) {
  event.notification.close();
  const path = event.notification.data.path;
  event.waitUntil(
    clients.openWindow(path)
  );
});