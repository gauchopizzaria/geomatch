self.addEventListener("push", async (event) => {
  let payload = { title: "GeoMatch", body: "Nova notificação!", data: { path: "/" } };

  if (event.data) {
    try {
      payload = await event.data.json();
    } catch (e) {
      payload.body = event.data.text();
    }
  }

  // 1. Tenta encontrar abas abertas da aplicação
  const allClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
  
  let notifiedNatively = false;

  // 2. Itera sobre os clientes para tentar enviar a mensagem para a ponte Android
  for (const client of allClients) {
    // Envia mensagem para o arquivo JS que está na página (ex: push_notifications.js)
    client.postMessage({
      type: 'PUSH_RECEIVED',
      title: payload.title,
      body: payload.body,
      path: payload.data.path
    });
    notifiedNatively = true;
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