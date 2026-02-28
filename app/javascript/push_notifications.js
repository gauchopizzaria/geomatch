// app/javascript/push_notifications.js


// Função para lidar com mensagens vindas do Service Worker
const setupServiceWorkerMessageListener = () => {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', (event) => {
      if (event.data && event.data.type === 'PUSH_RECEIVED') {
        console.log("Mensagem Push recebida do Worker:", event.data);
        
        // Verifica se a ponte nativa Android existe (WebView)
        if (typeof Android !== 'undefined' && Android.mostrarNotificacao) {
          Android.mostrarNotificacao(
            event.data.title, 
            event.data.body, 
            event.data.path
          );
        } else {
          console.log("Ponte Android não encontrada. Ignorando chamada nativa.");
        }
      }
    });
  }
};

document.addEventListener("turbo:load", () => {
  // Configura o ouvinte de mensagens IMEDIATAMENTE
  setupServiceWorkerMessageListener();
  
  // Verifica se o navegador suporta Service Workers e Push API
  if ("serviceWorker" in navigator && "PushManager" in window) {
    console.log("Service Worker e Push API suportados.");

    // 1. Registrar o Service Worker
    navigator.serviceWorker.register("/service-worker.js")
      .then(registration => {
        console.log("Service Worker registrado com sucesso:", registration);
        // Após o registro, tente se inscrever para notificações
        subscribeUserToPush(registration);
      })
      .catch(error => {
        console.error("Falha ao registrar o Service Worker:", error);
      });
  } else {
    console.warn("Notificações Push não suportadas neste navegador.");
  }
});

function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - base64String.length % 4) % 4);
  const base64 = (base64String + padding)
    .replace(/\-/g, '+')
    .replace(/_/g, '/');

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

  const applicationServerKey = applicationServerKeyElement.content;
  const convertedVapidKey = urlBase64ToUint8Array(applicationServerKey);

  // No mobile, é melhor pedir permissão explicitamente via interação do usuário
  // Mas aqui vamos garantir que a Promise seja tratada corretamente
  Notification.requestPermission().then(permission => {
    console.log("Status da permissão:", permission);
    if (permission === "granted") {
      registration.pushManager.getSubscription().then(existingSubscription => {
        if (existingSubscription) return existingSubscription;

        return registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: convertedVapidKey
        });
      })
      .then(subscription => {
        sendSubscriptionToBackend(subscription);
      })
      .catch(error => console.error("Erro na inscrição Push:", error));
    }
  });
}

function sendSubscriptionToBackend(subscription) {
  const subscriptionData = subscription.toJSON();

  fetch("/push_subscriptions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
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

document.addEventListener("turbo:load", () => {
  if ("serviceWorker" in navigator && "PushManager" in window) {
    navigator.serviceWorker.register("/service-worker.js")
      .then(registration => {
        subscribeUserToPush(registration);
      });
  }
});


// Opcional: Adicionar lógica para desinscrever o usuário
function unsubscribeUserFromPush() {
  navigator.serviceWorker.ready.then(registration => {
    registration.pushManager.getSubscription().then(subscription => {
      if (subscription) {
        subscription.unsubscribe().then(successful => {
          console.log("Usuário desinscrito com sucesso.");
          // Enviar solicitação para remover a inscrição do backend
          sendUnsubscriptionToBackend(subscription.endpoint);
        }).catch(error => {
          console.error("Falha ao desinscrever o usuário:", error);
        });
      }
    });
  });
}

function sendUnsubscriptionToBackend(endpoint) {
  fetch("/push_subscriptions", {
    method: "DELETE",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
    },
    body: JSON.stringify({ endpoint: endpoint })
  })
  .then(response => {
    if (response.ok) {
      console.log("Inscrição de Push removida do backend com sucesso.");
    } else {
      console.error("Falha ao remover inscrição de Push do backend.");
    }
  })
  .catch(error => {
    console.error("Erro de rede ao remover inscrição de Push:", error);
  });
}