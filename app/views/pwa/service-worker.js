// service-worker.js

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