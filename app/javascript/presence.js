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

console.log(`[Presence] Módulo carregado. isTurboNative=${isTurboNative}`);

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
    const lat  = window._presenceLat;
    const lng  = window._presenceLng;
    const now  = new Date().toISOString();
    const audio = _audioKeepAlive;
    const audioState = audio
      ? `paused=${audio.paused} readyState=${audio.readyState} currentTime=${audio.currentTime.toFixed(1)}`
      : 'null (não inicializado)';

    // Este log é o indicador principal: se aparecer no Remote Inspector após
    // minimizar, significa que o JS NÃO foi suspenso (audio keep-alive funcional).
    console.log(`[Presence/Heartbeat] ⏱ ${now} | lat=${lat?.toFixed(5) ?? '—'} lng=${lng?.toFixed(5) ?? '—'} | audio: ${audioState}`);

    if (!lat || !lng) return;

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content ?? '';
    fetch('/users/update_location', {
      method:    'POST',
      keepalive: true,
      headers:   { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
      body:      JSON.stringify({ latitude: lat, longitude: lng })
    }).catch((err) => {
      console.warn(`[Presence/Heartbeat] fetch falhou: ${err.message}`);
    });
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
//
//   ATENÇÃO: preload='auto' + audio.load() são obrigatórios para que o ficheiro
//   já esteja em buffer no momento da primeira interação do utilizador. Sem isso,
//   o iOS pode rejeitar o .play() com NotSupportedError porque não há dados.
// =============================================================================

function setupAudioKeepAlive() {
  if (isTurboNative) {
    console.log('[Presence/Audio] App nativo detectado — keep-alive de áudio desativado.');
    return;
  }
  if (_audioKeepAlive) {
    const a = _audioKeepAlive;
    console.log(`[Presence/Audio] Já inicializado. paused=${a.paused} readyState=${a.readyState} src=${a.src}`);
    return;
  }

  console.log('[Presence/Audio] Criando elemento <audio> → /silence.mp3');
  const audio   = document.createElement('audio');
  audio.src     = '/silence.mp3';
  audio.loop    = true;
  audio.volume  = 0;
  // preload='auto': o browser carrega o ficheiro proativamente.
  // Sem isso o .play() pode falhar com NotSupportedError no primeiro gesto.
  audio.preload = 'auto';
  _audioKeepAlive = audio;

  audio.addEventListener('canplaythrough', () => {
    console.log(`[Presence/Audio] ✅ canplaythrough — áudio pronto para reprodução sem interrupções. readyState=${audio.readyState}`);
  }, { once: true });

  audio.addEventListener('error', () => {
    const err = audio.error;
    console.error(`[Presence/Audio] ❌ Erro ao carregar /silence.mp3 — code=${err?.code} message="${err?.message}"`);
  }, { once: true });

  // Inicia o carregamento imediatamente — o .play() terá dados disponíveis
  // quando o primeiro gesto do utilizador ocorrer.
  audio.load();
  console.log('[Presence/Audio] audio.load() chamado — aguardando canplaythrough...');

  // Factory: cria um handler nomeado por evento para identificar a origem nos logs.
  const makeActivateHandler = (eventName) => () => {
    console.log(`[Presence/Audio] Gesto detectado via "${eventName}". Estado: _active=${_audioKeepAlive === audio} paused=${audio.paused} readyState=${audio.readyState}`);

    if (_audioKeepAlive !== audio) {
      console.warn('[Presence/Audio] Elemento substituído por teardown — play() cancelado.');
      return;
    }

    audio.play()
      .then(() => {
        console.log(`[Presence/Audio] ✅ play() resolvido — áudio em loop. JS mantido ativo em 2º plano.`);
      })
      .catch((err) => {
        console.error(`[Presence/Audio] ❌ play() rejeitado — ${err.name}: "${err.message}". Política de autoplay bloqueou.`);
      });
  };

  // touchstart: dispara antes de click no iOS (cobre tap e scroll que termine como tap)
  // click: cobre mouse e teclado (Enter/Space)
  // once:true: cada listener se auto-remove após o primeiro disparo
  document.addEventListener('touchstart', makeActivateHandler('touchstart'), { passive: true, once: true });
  document.addEventListener('click',      makeActivateHandler('click'),      { once: true });

  console.log('[Presence/Audio] Listeners registados (touchstart + click, once=true). Aguardando primeiro gesto...');
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
    const state = document.visibilityState;
    const audio = _audioKeepAlive;
    const audioState = audio
      ? `paused=${audio.paused} readyState=${audio.readyState}`
      : 'null';

    console.log(`[Presence/Beacon] visibilitychange → state="${state}" | audio: ${audioState}`);

    if (state !== 'hidden') return;

    const lat  = window._presenceLat;
    const lng  = window._presenceLng;

    if (!lat || !lng) {
      console.warn('[Presence/Beacon] Beacon não enviado — lat/lng indisponível (usuário não tem posição ou está deslogado).');
      return;
    }

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content ?? '';
    const body = new URLSearchParams({
      authenticity_token: csrf,
      latitude:           lat,
      longitude:          lng
    });

    const accepted = navigator.sendBeacon(
      '/users/update_location',
      new Blob([body.toString()], { type: 'application/x-www-form-urlencoded' })
    );

    console.log(`[Presence/Beacon] sendBeacon(lat=${lat.toFixed(5)}, lng=${lng.toFixed(5)}) → ${accepted ? '✅ aceito pelo browser' : '❌ rejeitado pelo browser (payload > 64kb?)'}`);
  });

  console.log('[Presence/Beacon] Listener de visibilitychange registado.');
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
  console.log('[Presence] teardown() executado — subscrição, heartbeat e áudio encerrados.');
}
