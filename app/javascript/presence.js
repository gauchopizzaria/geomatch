// presence.js — Camada global de presença no mapa
//
// Este módulo é carregado no layout principal (autenticado) e vive durante toda
// a sessão do navegador. Ele mantém a subscrição ao MapChannel e um heartbeat
// de localização que continuam funcionando independentemente de qual aba o
// usuário esteja navegando. Assim, o marcador no mapa de outros usuários não
// some quando o usuário troca de tela.
//
// Arquitetura de colaboração com map_3d.js:
//   window.presenceSetLocation(lat, lng)  — chamado por map_3d.js com as coords
//   window.setMapRealtimeHandler(fn|null) — registra/limpa o handler de dados do canal

import consumer from "./channels/consumer";

let _sub      = null;  // Única subscrição ao MapChannel para toda a sessão
let _interval = null;  // Heartbeat de localização

// --- API pública consumida por map_3d.js ---

window.presenceSetLocation = (lat, lng) => {
  window._presenceLat = lat;
  window._presenceLng = lng;
};

window.setMapRealtimeHandler = (fn) => {
  window._mapRealtimeHandler = (typeof fn === 'function') ? fn : null;
};

// --- Gestão da subscrição ---

function ensureSubscribed() {
  if (_sub) return;

  _sub = consumer.subscriptions.create("MapChannel", {
    connected() {
      console.log('[Presence] MapChannel conectado globalmente');
    },
    disconnected() {
      console.log('[Presence] MapChannel desconectado — aguardando reconexão automática do ActionCable');
      _sub = null; // permite reentrância no próximo turbo:load
    },
    received(data) {
      // Delega para o handler da página do mapa (se ativo)
      if (typeof window._mapRealtimeHandler === 'function') {
        window._mapRealtimeHandler(data);
      }
    }
  });
}

// --- Heartbeat: mantém last_location_updated_at atualizado de qualquer página ---

function ensureHeartbeat() {
  if (_interval) return;

  _interval = setInterval(() => {
    const lat = window._presenceLat;
    const lng = window._presenceLng;
    if (!lat || !lng) return;

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content ?? '';
    fetch('/users/update_location', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
      body: JSON.stringify({ latitude: lat, longitude: lng })
    }).catch(() => {}); // falhas silenciosas — o servidor tentará novamente
  }, 60_000); // a cada 60s; o scope online_on_map usa 3 minutos como threshold
}

// --- Ciclo de vida ---

document.addEventListener('turbo:load', () => {
  // Só inicia presença para usuários logados
  if (!document.querySelector('meta[name="user-logged-in"]')) {
    teardown();
    return;
  }
  ensureSubscribed();
  ensureHeartbeat();
});

// Logout explícito: desmonta antes de a sessão ser destruída
// O MapChannel#unsubscribed no servidor cuidará do broadcast "leave"
document.addEventListener('turbo:before-visit', (e) => {
  const url = e.detail?.url ?? '';
  if (/sign_out|logout/.test(url)) teardown();
});

function teardown() {
  if (_sub)      { _sub.unsubscribe(); _sub = null; }
  if (_interval) { clearInterval(_interval); _interval = null; }
  window._presenceLat       = null;
  window._presenceLng       = null;
  window._mapRealtimeHandler = null;
}
