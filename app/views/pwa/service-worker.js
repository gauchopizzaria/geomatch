// service-worker.js

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const data = event.notification.data || {};
  const path = data.path || data.url || "/";
  const targetUrl = new URL(path, self.location.origin).href;

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
      // Procura aba do GeoMatch já aberta
      const existing = windowClients.find(c => c.url.startsWith(self.location.origin));

      if (existing) {
        // navigate() devolve um novo WindowClient — é nele que chamamos focus()
        return existing.navigate(targetUrl).then((navigated) => {
          const target = navigated || existing;
          return target.focus();
        });
      }

      // Nenhuma aba aberta — abre nova diretamente
      return clients.openWindow(targetUrl);
    })
  );
});

self.addEventListener("push", (event) => { // Remova o async daqui
  let payload = { title: "GeoMatch", body: "Nova notificação!", data: { path: "/" } };

  if (event.data) {
    try {
      // Use o método síncrono .json() para garantir compatibilidade na WebView
      payload = event.data.json();
    } catch (e) {
      payload.body = event.data.text();
    }
  }

  // Envolva tudo em um waitUntil para o Service Worker não "dormir" antes de terminar
  event.waitUntil((async () => {
    // 1. Tenta a ponte nativa Android primeiro
    if (typeof Android !== 'undefined' && Android.mostrarNotificacao) {
      Android.mostrarNotificacao(payload.title, payload.body, payload.data.path || "/");
    } 
    // 2. Se não for Android ou a ponte falhar, tenta as janelas abertas
    else {
      const allClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
      
      if (allClients.length > 0) {
        allClients.forEach(client => {
          client.postMessage({
            type: 'PUSH_RECEIVED',
            title: payload.title,
            body: payload.body,
            path: payload.data ? payload.data.path : "/"
          });
        });
      } else {
        // 3. Fallback para notificação padrão do navegador
        const options = {
          body: payload.body,
          data: payload.data,
          icon: '/assets/logo.png', // Verifique se este caminho existe
          badge: '/assets/logo.png'
        };
        await self.registration.showNotification(payload.title, options);
      }
    }
  })());
});