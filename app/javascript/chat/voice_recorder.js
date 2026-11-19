// Gravador de mensagem de voz do chat (microfone à direita do campo).
//
//   segurar o microfone ........ grava; soltar envia
//   deslizar para a esquerda ... cancela
//   deslizar para cima ......... trava a gravação (mãos livres): apagar, pausar, enviar
//   Enter/Espaço no microfone .. já começa travada (teclado e leitor de tela)
//
// O que sai daqui (onSend): o arquivo gravado, a duração e os picos da onda — o balão é
// desenhado com esses picos, sem precisar abrir o áudio de novo.
//
// Estados: idle → starting (pedindo o microfone) → holding | locked → idle
//
// Vibrações (chat/haptics.js), como no WhatsApp: ao começar a gravar, ao travar, ao
// cancelar, ao enviar, ao pausar/continuar e no toque rápido ("segure para gravar").

import { formatDuration } from "./audio_player";
import { haptic } from "./haptics";

// Em ordem de preferência. AAC em mp4 toca em qualquer aparelho; webm/opus é o que os
// navegadores sem mp4 gravam (o servidor converte na entrega quando precisa).
const MIME_CANDIDATES = [
  "audio/mp4;codecs=mp4a.40.2",
  "audio/webm;codecs=opus",
  "audio/mp4",
  "audio/webm",
  "audio/ogg;codecs=opus"
];

const CANCEL_DISTANCE = 110; // px para a esquerda: cancela
const LOCK_DISTANCE   = 64;  // px para cima: trava
const LEVEL_INTERVAL  = 80;  // ms entre as medições do volume
const LIVE_BARS       = 28;  // barras da onda ao vivo (gravação travada)
const HOLD_HINT       = "Segure o microfone para gravar e solte para enviar.";

export function voiceRecordingSupported() {
  return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder);
}

function pickMimeType() {
  if (typeof MediaRecorder.isTypeSupported !== "function") return "";
  return MIME_CANDIDATES.find((type) => MediaRecorder.isTypeSupported(type)) || "";
}

function microphoneErrorText(error) {
  switch (error && error.name) {
    case "NotAllowedError":
    case "SecurityError":
      return "Permita o uso do microfone para gravar áudio.";
    case "NotFoundError":
    case "OverconstrainedError":
      return "Nenhum microfone encontrado neste aparelho.";
    default:
      return "Não foi possível usar o microfone agora.";
  }
}

// Volumes medidos durante a gravação (0–1) → `count` picos de 8 a 100 para o balão.
// O mais alto vira 100: áudio falado baixinho ainda desenha uma onda com forma.
export function buildPeaks(levels, count) {
  const loudest = levels.reduce((max, level) => Math.max(max, level), 0);

  // Sem medição (o aparelho não liberou o medidor de volume): onda neutra, não uma linha reta
  if (!levels.length || loudest < 0.02) {
    return Array.from({ length: count }, (_, index) => 30 + Math.round(22 * Math.abs(Math.sin(index * 1.7)) + 14 * Math.abs(Math.sin(index * 0.6))));
  }

  return Array.from({ length: count }, (_, index) => {
    const from = Math.floor(index * levels.length / count);
    const to   = Math.max(from + 1, Math.floor((index + 1) * levels.length / count));
    let peak = 0;
    for (let i = from; i < to && i < levels.length; i++) peak = Math.max(peak, levels[i]);
    return Math.round(Math.max(0.08, peak / loudest) * 100);
  });
}

export function createVoiceRecorder({ composer, micButton, onSend, onNotice, onStateChange }) {
  const holdBar    = composer.querySelector("#rec-hold");
  const lockPill   = composer.querySelector("#rec-lock");
  const lockedBar  = composer.querySelector("#rec-locked");
  const holdTime   = composer.querySelector("#rec-hold-time");
  const lockedTime = composer.querySelector("#rec-locked-time");
  const liveWave   = composer.querySelector("#rec-wave");
  const pauseBtn   = composer.querySelector("#rec-pause");
  const trashBtn   = composer.querySelector("#rec-trash");
  const sendBtn    = composer.querySelector("#rec-send");

  const MAX_MS = (parseInt(composer.dataset.maxDuration, 10) || 180) * 1000;
  const MIN_MS = (parseFloat(composer.dataset.minDuration) || 1) * 1000;
  const PEAKS  = parseInt(composer.dataset.peaks, 10) || 32;

  let state = "idle";
  let session = null;      // a gravação em andamento
  let pointer = null;      // dedo/mouse que está segurando o microfone
  let audioContext = null; // medidor de volume (um só por conversa)

  const notice = (text, isError = false) => { if (onNotice) onNotice(text, isError); };

  function setState(next) {
    state = next;
    if (onStateChange) onStateChange(next);
  }

  // ---------------------------------------------------------------
  //   TELA
  // ---------------------------------------------------------------
  if (liveWave && !liveWave.children.length) {
    liveWave.innerHTML = "<i></i>".repeat(LIVE_BARS);
  }

  function showHold() {
    composer.classList.add("is-holding");
    holdBar.hidden = false;
    lockPill.hidden = false;
  }

  function showLocked() {
    composer.classList.remove("is-holding");
    composer.classList.add("is-locked");
    setDrag(0, 0);
    holdBar.hidden = true;
    lockPill.hidden = true;
    lockedBar.hidden = false;
  }

  function resetScreen() {
    composer.classList.remove("is-holding", "is-locked", "is-paused", "is-limit");
    setDrag(0, 0);
    holdBar.hidden = true;
    lockPill.hidden = true;
    lockedBar.hidden = true;
    paintTime(0);
    if (liveWave) Array.from(liveWave.children).forEach((bar) => { bar.style.height = ""; });
    if (pauseBtn) {
      pauseBtn.disabled = false;
      pauseBtn.setAttribute("aria-label", "Pausar gravação");
    }
  }

  // Quanto o dedo andou: o microfone acompanha, o "Deslize para cancelar" some aos
  // poucos para a esquerda e o cadeado sobe (ver chat_media.scss)
  function setDrag(dx, dy) {
    composer.style.setProperty("--rec-dx", `${dx}px`);
    composer.style.setProperty("--rec-dy", `${dy}px`);
    composer.style.setProperty("--rec-cancel", Math.min(-dx / CANCEL_DISTANCE, 1).toFixed(2));
    composer.style.setProperty("--rec-lock", Math.min(-dy / LOCK_DISTANCE, 1).toFixed(2));
  }

  function paintTime(ms) {
    const label = formatDuration(Math.floor(ms / 1000));
    if (holdTime) holdTime.textContent = label;
    if (lockedTime) lockedTime.textContent = label;
  }

  // As últimas medições, da mais antiga (esquerda) para a mais nova (direita)
  function paintLiveWave(levels) {
    if (!liveWave) return;
    const bars = liveWave.children;
    const offset = levels.length - bars.length;
    for (let i = 0; i < bars.length; i++) {
      const level = offset + i >= 0 ? levels[offset + i] : 0;
      bars[i].style.height = `${Math.max(12, Math.round(level * 100))}%`;
    }
  }

  // ---------------------------------------------------------------
  //   MEDIDOR DE VOLUME (onda ao vivo e picos do balão)
  // ---------------------------------------------------------------
  // Criado dentro do toque: o iOS só deixa o AudioContext rodar a partir de um gesto.
  function prepareMeter() {
    try {
      const Context = window.AudioContext || window.webkitAudioContext;
      if (!Context) return;
      audioContext = audioContext || new Context();
      if (audioContext.state === "suspended") audioContext.resume().catch(() => {});
    } catch (_) {
      audioContext = null;
    }
  }

  function connectMeter(recording) {
    if (!audioContext) return;
    try {
      recording.source = audioContext.createMediaStreamSource(recording.stream);
      recording.analyser = audioContext.createAnalyser();
      recording.analyser.fftSize = 512;
      recording.source.connect(recording.analyser);
      recording.buffer = new Uint8Array(recording.analyser.fftSize);
    } catch (_) {
      recording.analyser = null;
    }
  }

  function sampleLevel(recording) {
    if (!recording.analyser) return 0;

    recording.analyser.getByteTimeDomainData(recording.buffer);
    let peak = 0;
    for (let i = 0; i < recording.buffer.length; i++) {
      peak = Math.max(peak, Math.abs(recording.buffer[i] - 128));
    }
    // Raiz: a fala normal ocupa só o começo da escala; assim ela já desenha barras visíveis
    return Math.min(1, Math.sqrt(peak / 128) * 1.25);
  }

  // ---------------------------------------------------------------
  //   GRAVAÇÃO
  // ---------------------------------------------------------------
  function elapsedMs(recording) {
    if (!recording.recorder) return 0;
    return recording.accumulated + (recording.paused ? 0 : performance.now() - recording.segmentStart);
  }

  async function begin(mode) {
    if (state !== "idle") return;
    if (!voiceRecordingSupported()) {
      notice("Não dá para gravar áudio neste navegador.", true);
      return;
    }

    const recording = { mode, released: false, levels: [], chunks: [], accumulated: 0, segmentStart: 0, paused: false };
    session = recording;
    setState("starting");
    if (mode === "hold") showHold(); else showLocked();
    prepareMeter();

    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, channelCount: 1 }
      });
    } catch (error) {
      if (session === recording) {
        abandon();
        notice(microphoneErrorText(error), true);
      }
      return;
    }

    // Cancelada enquanto o microfone abria
    if (session !== recording) {
      stream.getTracks().forEach((track) => track.stop());
      return;
    }
    recording.stream = stream;

    // Soltou antes de o microfone abrir: toque rápido, ou o aviso de permissão do
    // sistema apareceu por cima (na primeira vez) e levou o toque embora
    if (recording.mode === "hold" && recording.released) {
      abandon();
      notice(HOLD_HINT);
      return;
    }

    try {
      const mimeType = pickMimeType();
      recording.mimeType = mimeType;
      recording.recorder = new MediaRecorder(stream, mimeType ? { mimeType, audioBitsPerSecond: 48000 } : {});
      recording.recorder.ondataavailable = (event) => {
        if (event.data && event.data.size) recording.chunks.push(event.data);
      };
      recording.recorder.start();
    } catch (error) {
      console.error("[chat] MediaRecorder", error);
      abandon();
      notice("Não foi possível iniciar a gravação.", true);
      return;
    }

    connectMeter(recording);
    recording.segmentStart = performance.now();
    recording.timer = setInterval(() => tick(recording), LEVEL_INTERVAL);
    if (pauseBtn) pauseBtn.hidden = typeof recording.recorder.pause !== "function";
    haptic("start"); // o microfone abriu: está gravando a partir daqui
    setState(recording.mode === "hold" ? "holding" : "locked");
  }

  function tick(recording) {
    if (session !== recording) return;

    const elapsed = elapsedMs(recording);
    paintTime(elapsed);
    if (recording.paused) return;

    recording.levels.push(sampleLevel(recording));
    paintLiveWave(recording.levels);
    if (elapsed >= MAX_MS) reachLimit(recording);
  }

  // Tempo máximo: para de gravar e deixa a pessoa decidir (enviar ou apagar)
  function reachLimit(recording) {
    if (state === "holding") lock();
    if (!recording.paused) togglePause();
    composer.classList.add("is-limit");
    if (pauseBtn) pauseBtn.disabled = true;
    haptic("limit");
    notice(`O áudio chegou ao limite de ${Math.round(MAX_MS / 60000)} minutos. Envie ou apague.`);
  }

  function lock() {
    if (!session || state === "idle") return;
    releasePointer();
    session.mode = "locked";
    showLocked();
    if (state === "holding") setState("locked");
  }

  function togglePause() {
    const recording = session;
    if (!recording || !recording.recorder) return;

    if (recording.paused) {
      try { recording.recorder.resume(); } catch (_) { return; }
      recording.paused = false;
      recording.segmentStart = performance.now();
    } else {
      recording.accumulated = elapsedMs(recording);
      recording.paused = true;
      try { recording.recorder.pause(); } catch (_) { /* segue contando o tempo parado */ }
    }

    composer.classList.toggle("is-paused", recording.paused);
    if (pauseBtn) pauseBtn.setAttribute("aria-label", recording.paused ? "Continuar gravação" : "Pausar gravação");
  }

  // Solta microfone, medidor e relógio (o indicador de gravação do sistema some)
  function releaseHardware(recording) {
    clearInterval(recording.timer);
    try { if (recording.source) recording.source.disconnect(); } catch (_) { /* já desconectado */ }
    if (recording.stream) recording.stream.getTracks().forEach((track) => track.stop());
  }

  function releasePointer() {
    if (!pointer) return;
    try { micButton.releasePointerCapture(pointer.id); } catch (_) { /* captura já solta */ }
    pointer = null;
  }

  // Encerra sem enviar (cancelar, erro, saiu da conversa)
  function abandon() {
    const recording = session;
    session = null;
    releasePointer();
    resetScreen();

    if (recording) {
      if (recording.recorder && recording.recorder.state !== "inactive") {
        recording.recorder.ondataavailable = null;
        try { recording.recorder.stop(); } catch (_) { /* já parado */ }
      }
      releaseHardware(recording);
    }
    if (state !== "idle") setState("idle");
  }

  function finish() {
    const recording = session;
    if (!recording || !recording.recorder) { abandon(); return; }

    const elapsed = elapsedMs(recording);
    if (elapsed < MIN_MS) {
      abandon();
      haptic("tap");
      notice(HOLD_HINT);
      return;
    }

    haptic("send");
    const peaks = buildPeaks(recording.levels, PEAKS);
    session = null;
    releasePointer();
    resetScreen();
    setState("idle");

    stopRecorder(recording).then((blob) => {
      if (!blob || !blob.size) {
        notice("A gravação saiu vazia. Tente de novo.", true);
        return;
      }
      onSend({ blob, duration: Math.min(elapsed, MAX_MS) / 1000, peaks });
    });
  }

  function stopRecorder(recording) {
    return new Promise((resolve) => {
      const recorder = recording.recorder;
      const done = () => {
        releaseHardware(recording);
        // Navegador antigo sem mimeType: quem não informa é o Safari, que grava mp4
        const type = recorder.mimeType || recording.mimeType || "audio/mp4";
        resolve(recording.chunks.length ? new Blob(recording.chunks, { type }) : null);
      };

      if (recorder.state === "inactive") { done(); return; }
      recorder.onstop = done;
      recorder.onerror = done;
      try { recorder.stop(); } catch (_) { done(); }
    });
  }

  // ---------------------------------------------------------------
  //   MICROFONE: segurar, deslizar, soltar
  // ---------------------------------------------------------------
  micButton.addEventListener("pointerdown", (event) => {
    if (event.button > 0 || state !== "idle") return;

    event.preventDefault(); // não tira o foco do campo (o teclado fica como está)
    try { micButton.setPointerCapture(event.pointerId); } catch (_) { /* sem captura: segue pelos eventos do botão */ }
    pointer = { id: event.pointerId, x: event.clientX, y: event.clientY };
    begin("hold");
  });

  micButton.addEventListener("pointermove", (event) => {
    if (!pointer || event.pointerId !== pointer.id || state !== "holding") return;

    const dx = Math.min(0, event.clientX - pointer.x);
    const dy = Math.min(0, event.clientY - pointer.y);

    if (-dx >= CANCEL_DISTANCE && -dx > -dy) {
      haptic("cancel");
      abandon();
    } else if (-dy >= LOCK_DISTANCE && -dy >= -dx) {
      haptic("lock");
      lock();
    } else {
      setDrag(dx, dy);
    }
  });

  function onPointerEnd(event, takenBySystem) {
    if (!pointer || event.pointerId !== pointer.id) return;
    pointer = null;

    if (state === "starting") {
      if (session && session.mode === "hold") {
        session.released = true;
        haptic("tap");
      }
      return;
    }
    if (state !== "holding") return;

    // O sistema tomou o toque (ligação, gesto da borda…): trava em vez de jogar fora
    if (takenBySystem) lock(); else finish();
  }

  micButton.addEventListener("pointerup", (event) => onPointerEnd(event, false));
  micButton.addEventListener("pointercancel", (event) => onPointerEnd(event, true));
  micButton.addEventListener("contextmenu", (event) => event.preventDefault());

  // Teclado / leitor de tela (clique sem ponteiro tem detail 0)
  micButton.addEventListener("click", (event) => {
    if (event.detail === 0) begin("locked");
  });

  // ---------------------------------------------------------------
  //   GRAVAÇÃO TRAVADA: apagar, pausar/continuar, enviar
  // ---------------------------------------------------------------
  if (trashBtn) trashBtn.addEventListener("click", () => { haptic("cancel"); abandon(); });
  if (pauseBtn) pauseBtn.addEventListener("click", () => { haptic("tick"); togglePause(); });
  if (sendBtn) sendBtn.addEventListener("click", finish);

  // App em segundo plano: o sistema corta o microfone. Trava e pausa para não perder
  // o que já foi gravado.
  const onVisibility = () => {
    if (!document.hidden || !session || !session.recorder) return;
    if (state === "holding") lock();
    if (!session.paused) togglePause();
  };
  document.addEventListener("visibilitychange", onVisibility);

  return {
    isActive: () => state !== "idle",
    cancel: abandon,

    // Saiu da conversa: encerra tudo e solta o medidor
    destroy() {
      abandon();
      document.removeEventListener("visibilitychange", onVisibility);
      if (audioContext) {
        audioContext.close().catch(() => {});
        audioContext = null;
      }
    }
  };
}
