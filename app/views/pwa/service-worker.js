self.addEventListener("push", async (event) => {
  let payload = { title: "GeoMatch", body: "Nova notificação!", data: { path: "/" } };

  if (event.data) {
    try {
      payload = await event.data.json();
    } catch (e) {
      payload.body = event.data.text();
    }
  }

  // 1. Tenta a ponte nativa Android primeiro (O que funcionou no seu teste)
  if (typeof Android !== 'undefined' && Android.mostrarNotificacao) {
    Android.mostrarNotificacao(payload.title, payload.body, payload.data.path);
  } 
  // 2. Se não for Android, tenta avisar as janelas abertas (Página do JS)
  else {
    const allClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    
    if (allClients.length > 0) {
      allClients.forEach(client => {
        client.postMessage({
          type: 'PUSH_RECEIVED',
          title: payload.title,
          body: payload.body,
          path: payload.data.path
        });
      });
    } else {
      // 3. Fallback final apenas se não houver outra opção
      const options = {
        body: payload.body,
        data: payload.data,
        icon: '/icon.png'
      };
      // Usamos uma verificação extra para evitar o erro do print
      if (self.registration && 'showNotification' in self.registration) {
        event.waitUntil(self.registration.showNotification(payload.title, options));
      }
    }
  }
});

self.addEventListener("notificationclick", function(event) {
  event.notification.close();
  const path = event.notification.data.path;
  event.waitUntil(
    clients.openWindow(path)
  );
});