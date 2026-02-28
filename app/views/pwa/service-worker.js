self.addEventListener("push", async (event) => {
  let payload = { title: "GeoMatch", body: "Nova notificação!", data: { path: "/" } };

  if (event.data) {
    try {
      payload = await event.data.json();
    } catch (e) {
      payload.body = event.data.text();
    }
  }

 // Tenta a ponte nativa primeiro
  if (self.Android && typeof self.Android.mostrarNotificacao === 'function') {
      self.Android.mostrarNotificacao(payload.title, payload.body, payload.data.path);
  } else {
      // Fallback seguro usando self.registration
      const options = {
          body: payload.body,
          data: payload.data
      };
      event.waitUntil(self.registration.showNotification(payload.title, options));
  }

  // 3. Se não houver abas abertas (App em background total), usamos o fallback padrão
  // No Android, se o app está fechado, o sistema gerencia o Push via FCM/WebPush
  if (!notifiedNatively) {
    const options = {
      body: payload.body,
      icon: '/icon.png',
      data: payload.data,
      vibrate: [100, 50, 100]
    };
    event.waitUntil(self.registration.showNotification(payload.title, options));
  }
});

self.addEventListener("notificationclick", function(event) {
  event.notification.close();
  const path = event.notification.data.path;
  event.waitUntil(
    clients.openWindow(path)
  );
});