// Vibrações do chat (parecidas com as do WhatsApp).
//
//   haptic("start")  começou a gravar (segurando o microfone)
//   haptic("tap")    toque rápido no microfone: "segure para gravar"
//   haptic("lock")   gravação travada (deslizou para cima)
//   haptic("cancel") gravação cancelada (deslizou para a esquerda / lixeira)
//   haptic("send")   áudio enviado
//   haptic("tick")   pausar / continuar
//   haptic("limit")  chegou ao tempo máximo
//   haptic("menu")   toque longo numa mensagem (menu)
//   haptic("reply")  arrastou a mensagem o bastante para responder
//
// Três caminhos, nesta ordem:
//   1. App iOS: o WKWebView não tem navigator.vibrate. Se o app registrar o handler
//      "hapticHandler", ele recebe { style } e toca o UIFeedbackGenerator do iPhone.
//   2. Android / Chrome: navigator.vibrate com um padrão curto por evento.
//   3. Safari do iPhone (iOS 18+): tocar num <input type="checkbox" switch> faz o
//      próprio sistema dar um "toque" leve. É o único jeito sem app nativo; dá um toque
//      só (não tem intensidade).

// Estilo do UIFeedbackGenerator para o app iOS
//   light/medium/heavy/rigid/soft → UIImpactFeedbackGenerator
//   selection                     → UISelectionFeedbackGenerator
//   success/warning/error         → UINotificationFeedbackGenerator
const IOS_STYLES = {
  start:  "medium",
  tap:    "light",
  lock:   "rigid",
  cancel: "warning",
  send:   "light",
  tick:   "selection",
  limit:  "warning",
  menu:   "medium",
  reply:  "light"
};

// Padrões do navigator.vibrate (ms: vibra, pausa, vibra…)
const ANDROID_PATTERNS = {
  start:  28,
  tap:    [12, 60, 12],
  lock:   18,
  cancel: [18, 70, 18],
  send:   12,
  tick:   8,
  limit:  [25, 90, 25],
  menu:   35,
  reply:  12
};

// Quantos "toques" o truque do Safari dá em cada evento
const SAFARI_TICKS = { cancel: 2, limit: 2, tap: 2 };

const isIOS = () =>
  /iP(hone|ad|od)/.test(navigator.userAgent) ||
  (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1); // iPad "desktop"

function nativeHandler() {
  return window.webkit?.messageHandlers?.hapticHandler || null;
}

// Truque do Safari: um interruptor escondido; clicar no rótulo dele faz o iOS vibrar.
// Os cliques não sobem para a página (fechariam menus abertos).
function safariTick() {
  const label = document.createElement("label");
  label.setAttribute("aria-hidden", "true");
  label.style.display = "none";

  const input = document.createElement("input");
  input.type = "checkbox";
  input.setAttribute("switch", "");
  input.tabIndex = -1;
  label.appendChild(input);

  const stop = (event) => event.stopPropagation();
  label.addEventListener("click", stop);
  input.addEventListener("click", stop);
  input.addEventListener("change", stop);

  document.head.appendChild(label);
  label.click();
  label.remove();
}

export function haptic(kind) {
  try {
    const handler = nativeHandler();
    if (handler) {
      handler.postMessage({ style: IOS_STYLES[kind] || "light", event: kind });
      return;
    }

    if (typeof navigator.vibrate === "function") {
      navigator.vibrate(ANDROID_PATTERNS[kind] ?? 10);
      return;
    }

    if (isIOS()) {
      safariTick();
      if ((SAFARI_TICKS[kind] || 1) > 1) setTimeout(safariTick, 90);
    }
  } catch (_) {
    // Vibração é enfeite: nunca pode atrapalhar gravar ou enviar
  }
}
