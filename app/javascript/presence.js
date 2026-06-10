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
//
// Estratégias de keep-alive (Safari PWA apenas — não aplicadas no app nativo):
//   1. Silent Audio Loop  — mantém o JS ativo em segundo plano no iOS Safari
//   2. fetch keepalive    — heartbeat sobrevive ao unload/background
//   3. Beacon API         — envia última posição no momento em que a aba é ocultada

import consumer from "./channels/consumer";

// Detecta app nativo iOS (WkWebView com bridge Swift injetada).
// No app nativo o background location é gerido pela camada Swift via
// window.handleNativeLocationUpdate (live_location.js).
// As estratégias de keep-alive de áudio e beacon só se aplicam ao Safari (PWA).
const isTurboNative = !!window.webkit?.messageHandlers?.locationHandler;

let _sub            = null;   // Subscrição única ao MapChannel para toda a sessão
let _interval       = null;   // Timer do heartbeat
let _audioKeepAlive = null;   // Elemento <audio> silencioso (Safari keep-alive)
let _beaconSetup    = false;  // Guard: evita registar o visibilitychange mais de uma vez

// =============================================================================
//   API pública consumida por map_3d.js
// =============================================================================

window.presenceSetLocation = (lat, lng) => {
  window._presenceLat = lat;
  window._presenceLng = lng;
};

window.setMapRealtimeHandler = (fn) => {
  window._mapRealtimeHandler = (typeof fn === 'function') ? fn : null;
};

// =============================================================================
//   MapChannel — subscrição única por sessão
// =============================================================================

function ensureSubscribed() {
  if (_sub) return;

  _sub = consumer.subscriptions.create("MapChannel", {
    connected() {
      console.log('[Presence] MapChannel conectado globalmente');
      // Re-transmite a posição imediatamente ao (re)conectar — garante que o
      // utilizador reaparece no mapa dos outros após desbloqueio do ecrã.
      const lat  = window._presenceLat;
      const lng  = window._presenceLng;
      if (!lat || !lng) return;
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content ?? '';
      fetch('/users/update_location', {
        method:    'POST',
        keepalive: true,
        headers:   { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
        body:      JSON.stringify({ latitude: lat, longitude: lng })
      }).catch(() => {});
    },
    disconnected() {
      console.log('[Presence] MapChannel desconectado — ActionCable reconectará automaticamente');
      // NÃO limpar _sub: o ActionCable gere a reconexão internamente.
    },
    received(data) {
      if (typeof window._mapRealtimeHandler === 'function') {
        window._mapRealtimeHandler(data);
      }
    }
  });
}

// =============================================================================
//   Heartbeat — 30s, com keepalive para sobreviver ao background no iOS Safari
// =============================================================================

function ensureHeartbeat() {
  if (_interval) return;

  _interval = setInterval(() => {
    const lat = window._presenceLat;
    const lng = window._presenceLng;
    if (!lat || !lng) return;

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content ?? '';
    fetch('/users/update_location', {
      method:    'POST',
      keepalive: true, // o browser garante o envio mesmo após o unload/background
      headers:   { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
      body:      JSON.stringify({ latitude: lat, longitude: lng })
    }).catch(() => {});
  }, 30_000);
}

// =============================================================================
//   Silent Audio Keep-Alive (Safari PWA apenas)
//
//   iOS Safari suspende o JavaScript quando a aba é minimizada ou o ecrã é
//   bloqueado — a menos que haja áudio em reprodução. A solução padrão é um
//   ficheiro MP3 silencioso em loop que "engana" o browser e mantém o event
//   loop vivo, permitindo que o heartbeat e o WebSocket continuem ativos.
//
//   Requisito do iOS: .play() deve ser chamado directamente no handler de um
//   gesto do utilizador (touchstart / click). Não pode ser chamado de forma
//   assíncrona ou por timeout, caso contrário a política de autoplay bloqueia.
// =============================================================================

function setupAudioKeepAlive() {
  if (isTurboNative || _audioKeepAlive) return;

  const audio    = document.createElement('audio');
  audio.src      = '/silence.mp3'; // ficheiro em public/silence.mp3
  audio.loop     = true;
  audio.volume   = 0;
  audio.preload  = 'none'; // não carrega até ao primeiro gesto
  _audioKeepAlive = audio;

  const activate = () => {
    // Verifica se ainda é o elemento activo — evita reprodução após teardown/logout.
    if (_audioKeepAlive === audio) audio.play().catch(() => {});
  };

  // Dois eventos para cobrir toque (iOS) e clique (desktop/trackpad).
  // once:true remove cada listener após o primeiro disparo.
  document.addEventListener('touchstart', activate, { passive: true, once: true });
  document.addEventListener('click',      activate, { once: true });
}

// =============================================================================
//   Beacon API — envia última posição ao ocultar a aba (Safari apenas)
//
//   navigator.sendBeacon não suporta headers customizados. Para que o Rails
//   valide o CSRF token, enviamos o campo authenticity_token no corpo do
//   pedido como application/x-www-form-urlencoded. O Rails lê este campo a
//   partir de params[:authenticity_token] antes de processar a action.
// =============================================================================

function setupVisibilityBeacon() {
  if (isTurboNative || _beaconSetup) return;
  _beaconSetup = true;

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'hidden') return;

    const lat  = window._presenceLat;
    const lng  = window._presenceLng;
    if (!lat || !lng) return; // sem posição disponível (ex: após logout)

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content ?? '';

    // Blob com content-type explícito: Rails faz parse como form params e
    // valida o CSRF via params[:authenticity_token].
    const body = new URLSearchParams({
      authenticity_token: csrf,
      latitude:           lat,
      longitude:          lng
    });

    navigator.sendBeacon(
      '/users/update_location',
      new Blob([body.toString()], { type: 'application/x-www-form-urlencoded' })
    );
  });
}

// =============================================================================
//   Ciclo de vida — Turbo
// =============================================================================

document.addEventListener('turbo:load', () => {
  if (!document.querySelector('meta[name="user-logged-in"]')) {
    teardown();
    return;
  }
  ensureSubscribed();
  ensureHeartbeat();
  setupAudioKeepAlive();   // idempotente: guard interno _audioKeepAlive
  setupVisibilityBeacon(); // idempotente: guard interno _beaconSetup
});

// Logout explícito: desmonta antes de a sessão ser destruída.
// O MapChannel#unsubscribed no servidor cuidará do broadcast "leave".
document.addEventListener('turbo:before-visit', (e) => {
  const url = e.detail?.url ?? '';
  if (/sign_out|logout/.test(url)) teardown();
});

function teardown() {
  if (_sub)            { _sub.unsubscribe();      _sub = null; }
  if (_interval)       { clearInterval(_interval); _interval = null; }
  if (_audioKeepAlive) { _audioKeepAlive.pause(); _audioKeepAlive = null; }
  window._presenceLat        = null;
  window._presenceLng        = null;
  window._mapRealtimeHandler = null;
  // _beaconSetup não é resetado: o listener permanece registado mas
  // retorna imediatamente por lat/lng nulos enquanto o utilizador está deslogado.
}
