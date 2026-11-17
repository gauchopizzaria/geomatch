// Player das mensagens de voz da conversa.
//
// Um <audio> só para a conversa inteira: tocar um balão para o que estava tocando.
// O balão (.msg-audio) traz o endereço e a duração nos data-attributes — a duração
// vem de quem gravou, porque o arquivo do MediaRecorder (webm) não informa a dele.
//
// Quem chama decide quando tocar (o chat trata os toques na fase de captura, junto
// com os gestos da conversa): aqui ficam só toggle / seek / stop.

// "0:07" — segundos completos, igual a MessageMedia.duration_label no servidor
export function formatDuration(seconds) {
  const total = Math.max(0, Math.floor(Number(seconds) || 0));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

export function createAudioPlayer({ onError } = {}) {
  const audio = new Audio();
  audio.preload = "auto";

  let current = null;        // .msg-audio tocando ou pausado no meio
  let triedFallback = false; // já tentou o endereço original (data-fallback-url)
  let pendingSeek = null;    // posição (0–1) pedida antes de o áudio carregar
  let frame = null;

  function durationOf(el) {
    const stored = parseFloat(el.dataset.duration);
    if (stored > 0) return stored;
    return Number.isFinite(audio.duration) ? audio.duration : 0;
  }

  // Barras já tocadas + tempo embaixo da onda
  function paint(el, ratio, seconds) {
    const bars = el.querySelectorAll(".msg-audio-wave i");
    const played = Math.round(Math.min(Math.max(ratio, 0), 1) * bars.length);
    bars.forEach((bar, index) => bar.classList.toggle("is-played", index < played));

    const time = el.querySelector(".msg-audio-time");
    if (time) time.textContent = formatDuration(seconds);
  }

  function setPlaying(el, playing) {
    el.classList.toggle("is-playing", playing);
    const button = el.querySelector(".msg-audio-play");
    if (button) button.setAttribute("aria-label", playing ? "Pausar áudio" : "Tocar áudio");
  }

  // Volta o balão ao estado de "não tocado": onda limpa e a duração total
  function reset(el) {
    if (!el) return;
    setPlaying(el, false);
    paint(el, 0, parseFloat(el.dataset.duration) || 0);
  }

  function paintProgress() {
    if (!current) return;
    const total = durationOf(current);
    paint(current, total ? audio.currentTime / total : 0, audio.currentTime);
  }

  function loop() {
    cancelAnimationFrame(frame);
    paintProgress();
    if (current && !audio.paused) frame = requestAnimationFrame(loop);
  }

  function play() {
    const el = current;
    const attempt = audio.play();
    if (attempt && attempt.catch) {
      attempt.catch((error) => {
        // Formato/endereço com problema chega pelo evento "error" (que tenta o original).
        // Aqui só o bloqueio do navegador: o botão volta a "tocar".
        if (error && error.name === "NotAllowedError" && current === el) setPlaying(el, false);
      });
    }
  }

  function start(el, ratio) {
    const url = el.dataset.url || el.dataset.fallbackUrl;
    if (!url) return;

    triedFallback = !el.dataset.url;
    current = el;
    pendingSeek = ratio > 0 ? ratio : null;
    audio.src = url;
    play();
  }

  function applySeek(ratio) {
    const total = durationOf(current);
    if (!total) return;

    try { audio.currentTime = Math.min(Math.max(ratio, 0), 0.999) * total; } catch (_) { /* ainda sem dados */ }
    paintProgress();
  }

  function stop() {
    if (!current) return;
    const el = current;
    current = null;
    pendingSeek = null;
    cancelAnimationFrame(frame);
    audio.pause();
    reset(el);
  }

  audio.addEventListener("play", () => { if (current) { setPlaying(current, true); loop(); } });
  audio.addEventListener("pause", () => { if (current) setPlaying(current, false); });
  audio.addEventListener("timeupdate", paintProgress); // aba em segundo plano não roda o rAF
  audio.addEventListener("loadedmetadata", () => {
    if (current && pendingSeek !== null) applySeek(pendingSeek);
    pendingSeek = null;
  });
  audio.addEventListener("ended", () => {
    const el = current;
    current = null;
    cancelAnimationFrame(frame);
    reset(el);
  });
  audio.addEventListener("error", () => {
    if (!current) return;

    // O endereço convertido falhou: tenta o arquivo como foi gravado
    const fallback = current.dataset.fallbackUrl;
    if (!triedFallback && fallback && fallback !== current.dataset.url) {
      triedFallback = true;
      audio.src = fallback;
      play();
      return;
    }

    const el = current;
    current = null;
    cancelAnimationFrame(frame);
    reset(el);
    if (onError) onError();
  });

  return {
    // Botão de tocar: toca, pausa ou troca de balão
    toggle(el) {
      if (current === el) {
        if (audio.paused) play(); else audio.pause();
        return;
      }
      stop();
      start(el, 0);
    },

    // Toque na onda: vai para aquele ponto (e começa a tocar se era outro balão)
    seek(el, ratio) {
      if (current !== el) {
        stop();
        start(el, ratio);
        return;
      }
      applySeek(ratio);
      if (audio.paused) play();
    },

    stop,

    // A mensagem saiu da tela (apagada, conversa limpa): para se era ela que tocava
    release(container) {
      if (current && container && container.contains(current)) stop();
    }
  };
}
