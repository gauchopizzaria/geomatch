// Vibrações do chat (parecidas com as do WhatsApp).
//
//   haptic("start")  encostou no microfone para gravar
//   haptic("lock")   gravação travada (deslizou para cima)
//   haptic("cancel") gravação cancelada (deslizou para a esquerda / lixeira)
//   haptic("send")   áudio enviado
//   haptic("tick")   pausar / continuar
//   haptic("limit")  chegou ao tempo máximo
//   haptic("menu")   toque longo numa mensagem (menu)
//   haptic("reply")  arrastou a mensagem o bastante para responder
//
// Como cada aparelho vibra:
//   1. App iOS com o handler nativo "hapticHandler": recebe { style, event } e toca o
//      UIFeedbackGenerator do iPhone. É o único jeito de vibrar no iPhone em qualquer
//      momento (ao encostar, ao travar, ao deslizar).
//   2. Android / Chrome: navigator.vibrate, com um padrão por evento.
//   3. iPhone sem o handler (Safari, ou o app antes de ter o handler): o iOS não deixa
//      página web vibrar. A única vibração que o WebKit toca é a do interruptor
//      <input type="checkbox" switch>, e só quando o DEDO toca nele de verdade — desde
//      o iOS 26.5 clicar nele pelo código (label.click()) não vibra mais, e antes disso
//      já não vibrava fora de um toque. Então: um <label class="haptic-tap"> transparente
//      fica por cima do microfone e dos botões da gravação, ligado a um interruptor
//      escondido; o toque real no botão passa pelo rótulo e o iPhone vibra.
//      Limite: só vibra em TOQUE (soltar o dedo sem arrastar). Encostar e segurar,
//      travar ou cancelar deslizando não geram toque — nesses o iPhone só vibra pelo app
//      com o handler nativo.

const IOS_STYLES = {
  start:  "medium",
  lock:   "rigid",
  cancel: "warning",
  send:   "light",
  tick:   "selection",
  limit:  "warning",
  menu:   "medium",
  reply:  "light"
};

const ANDROID_PATTERNS = {
  start:  28,
  lock:   18,
  cancel: [18, 70, 18],
  send:   12,
  tick:   8,
  limit:  [25, 90, 25],
  menu:   35,
  reply:  12
};

const isIOS = () =>
  /iP(hone|ad|od)/.test(navigator.userAgent) ||
  (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1); // iPad "desktop"

function nativeHandler() {
  return window.webkit?.messageHandlers?.hapticHandler || null;
}

// iPhone sem handler nativo e sem navigator.vibrate: vibra pelos rótulos do interruptor
export function usesSwitchHaptics() {
  return !nativeHandler() && typeof navigator.vibrate !== "function" && isIOS();
}

// Liga os rótulos .haptic-tap de `root` (só no iPhone sem handler: nos outros casos o
// haptic() já vibra, e o rótulo daria uma vibração a mais)
export function setupTapHaptics(root) {
  if (!root) return;

  const enabled = usesSwitchHaptics();
  root.classList.toggle("use-switch-haptics", enabled);
  if (!enabled) return;

  // O clique que o rótulo repassa ao interruptor não pode chegar à página (fecharia
  // menus abertos e contaria como toque fora)
  root.querySelectorAll("input.haptic-switch").forEach((input) => {
    if (input.dataset.hapticWired) return;
    input.dataset.hapticWired = "1";
    ["click", "change", "input"].forEach((type) => input.addEventListener(type, (event) => event.stopPropagation()));

    // O clique repassado pode pôr o foco no interruptor: devolve a quem tinha (com o
    // teclado aberto, tirar o foco do campo fecharia o teclado)
    input.addEventListener("focus", (event) => {
      const previous = event.relatedTarget;
      input.blur();
      if (previous && typeof previous.focus === "function") previous.focus({ preventScroll: true });
    });
  });
}

export function haptic(kind) {
  try {
    const handler = nativeHandler();
    if (handler) {
      handler.postMessage({ style: IOS_STYLES[kind] || "light", event: kind });
      return;
    }

    if (typeof navigator.vibrate === "function") navigator.vibrate(ANDROID_PATTERNS[kind] ?? 10);
    // iPhone sem handler: os rótulos .haptic-tap vibram no toque (ver acima)
  } catch (_) {
    // Vibração é enfeite: nunca pode atrapalhar gravar ou enviar
  }
}
