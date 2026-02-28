// app/javascript/push_notifications.js

// 1. Função para lidar com mensagens vindas do Service Worker (Ponte Android)
const setupServiceWorkerMessageListener = () => {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', (event) => {
      if (event.data && event.data.type === 'PUSH_RECEIVED') {
        console.log("Mensagem Push recebida do Worker:", event.data);

        // Garante que nunca envie 'undefined' para o Java convertendo para String
        const titulo = String(event.data.title || "GeoMatch");
        const msg    = String(event.data.body  || "Nova mensagem recebida");
        const rota   = String(event.data.path  || "/");

        // Verifica se a ponte nativa Android existe (WebView)
        if (typeof Android !== 'undefined' && Android.mostrarNotificacao) {
          Android.mostrarNotificacao(titulo, msg, rota);
          console.log("Notificação enviada para a ponte nativa Android.");
        } else {
          console.log("Ponte Android não encontrada. Ignorando chamada nativa.");
        }
      }
    });
  }
};

// 2. Inicialização Principal
document.addEventListener("turbo:load", () => {
  console.log("Iniciando verificação de Service Worker...");

  // Configura o ouvinte de mensagens imediatamente
  setupServiceWorkerMessageListener();

  const supportsPush = ("serviceWorker" in navigator && "PushManager" in window);
  const isAndroidWebView = (typeof Android !== 'undefined');

  if (supportsPush || isAndroidWebView) {
    console.log("Ambiente compatível detectado.");

    navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
      .then(registration => {
        console.log("Service Worker registrado com sucesso.");
        
        // Só tenta a inscrição Push se o navegador realmente suportar a API nativa de Push
        if ("PushManager" in window) {
          subscribeUserToPush(registration);
        } else {
          console.log("Usando apenas ponte nativa Android para notificações.");
        }
      })
      .catch(error => {
        console.error("Falha ao registrar o Service Worker:", error);
      });
  } else {
    console.warn("Notificações Push não suportadas e ponte Android não detectada.");
  }
});

// 3. Funções Auxiliares de Inscrição
function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - base64String.length % 4) % 4);
  const base64 = (base64String + padding).replace(/\-/g, '+').replace(/_/g, '/');
  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

function subscribeUserToPush(registration) {
  const applicationServerKeyElement = document.querySelector('meta[name="vapid-public-key"]');
  if (!applicationServerKeyElement) return;

  const notificationApi = window.Notification || self.Notification;

  if (notificationApi) {
    notificationApi.requestPermission().then(permission => {
      console.log("Status da permissão:", permission);
      if (permission === "granted") {
        registration.pushManager.getSubscription().then(existingSubscription => {
          if (existingSubscription) return existingSubscription;

          return registration.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: urlBase64ToUint8Array(applicationServerKeyElement.content)
          });
        })
        .then(subscription => {
          sendSubscriptionToBackend(subscription);
        })
        .catch(error => console.error("Erro na inscrição Push:", error));
      }
    });
  } else {
    console.warn("API de Notificação não encontrada neste ambiente.");
  }
}

function sendSubscriptionToBackend(subscription) {
  const subscriptionData = subscription.toJSON();
  const csrfToken = document.querySelector("meta[name='csrf-token']").content;

  fetch("/push_subscriptions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": csrfToken
    },
    body: JSON.stringify({
      push_subscription: {
        endpoint: subscriptionData.endpoint,
        p256dh: subscriptionData.keys.p256dh,
        auth: subscriptionData.keys.auth
      }
    })
  });
}

// 4. Lógica de Desinscrição (Opcional)
function unsubscribeUserFromPush() {
  navigator.serviceWorker.ready.then(registration => {
    registration.pushManager.getSubscription().then(subscription => {
      if (subscription) {
        subscription.unsubscribe().then(successful => {
          console.log("Usuário desinscrito com sucesso.");
          sendUnsubscriptionToBackend(subscription.endpoint);
        }).catch(error => {
          console.error("Falha ao desinscrever o usuário:", error);
        });
      }
    });
  });
}

function sendUnsubscriptionToBackend(endpoint) {
  const csrfToken = document.querySelector("meta[name='csrf-token']").content;

  fetch("/push_subscriptions", {
    method: "DELETE",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": csrfToken
    },
    body: JSON.stringify({ endpoint: endpoint })
  })
  .then(response => {
    if (response.ok) console.log("Inscrição removida do backend.");
  })
  .catch(error => console.error("Erro ao remover inscrição:", error));
}