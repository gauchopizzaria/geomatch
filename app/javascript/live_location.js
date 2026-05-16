let watchId = null;
let isTracking = false;
let lastLat = null;
let lastLng = null;
let nativeLocationCallback = null;

// Deslocamento mínimo real (metros) para propagar uma atualização de posição.
// Filtra o ruído inerente do GPS — o celular parado reporta variações de 1-4m continuamente.
const MIN_MOVE_METERS = 5;

function haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const φ1 = lat1 * Math.PI / 180;
  const φ2 = lat2 * Math.PI / 180;
  const Δφ = (lat2 - lat1) * Math.PI / 180;
  const Δλ = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(Δφ / 2) ** 2 + Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Inicia rastreamento direto — sempre liga, independente do estado anterior.
// Usar na inicialização da tela para garantir que o GPS começa ligado.
export function startLiveTracking(map, buttonElement, onLocationChange) {
  if (watchId !== null) {
    navigator.geolocation.clearWatch(watchId);
    watchId = null;
  }
  isTracking = false;
  lastLat = null;
  lastLng = null;
  startTracking(buttonElement, onLocationChange);
}

// Alterna entre ligado/desligado — usar no evento de click do botão.
export function toggleLiveTracking(map, buttonElement, onLocationChange) {
  if (isTracking) {
    stopTracking(buttonElement);
    return false;
  } else {
    startTracking(buttonElement, onLocationChange);
    return true;
  }
}

// Limpa estado do GPS sem efeitos colaterais de UI — usar no turbo:before-cache.
export function resetTracking(buttonElement) {
  if (watchId !== null) {
    navigator.geolocation.clearWatch(watchId);
    watchId = null;
  }
  isTracking = false;
  lastLat = null;
  lastLng = null;
  if (buttonElement) buttonElement.classList.remove("active-tracking");
}

// map não é mais usado internamente — parâmetro mantido nos exports para compatibilidade
function startTracking(buttonElement, onLocationChange) {
  if (!("geolocation" in navigator)) {
    alert("Geolocalização não suportada pelo seu navegador.");
    return;
  }

  isTracking = true;
  nativeLocationCallback = onLocationChange || null;
  if (buttonElement) buttonElement.classList.add("active-tracking");
  console.log("📍 Iniciando rastreamento contínuo...");

  if (window.webkit?.messageHandlers?.locationHandler) {
    window.webkit.messageHandlers.locationHandler.postMessage('startTracking');
  }

  watchId = navigator.geolocation.watchPosition(
    (position) => {
      const lat = position.coords.latitude;
      const lng = position.coords.longitude;

      // Filtra ruído GPS: ignora posições que não representam deslocamento real.
      // Primeiro fix sempre passa (lastLat === null) para inicializar a posição.
      if (lastLat !== null) {
        const dist = haversineMeters(lastLat, lastLng, lat, lng);
        if (dist < MIN_MOVE_METERS) return;
        console.log(`🚶 Movimento real detectado: ${dist.toFixed(1)}m → (${lat.toFixed(6)}, ${lng.toFixed(6)})`);
      } else {
        console.log(`📍 Posição inicial fixada: (${lat.toFixed(6)}, ${lng.toFixed(6)})`);
      }

      lastLat = lat;
      lastLng = lng;

      if (onLocationChange) onLocationChange(lat, lng);
    },
    (error) => {
      console.warn("⚠️ Erro no rastreamento contínuo:", error.message);
      stopTracking(buttonElement);
    },
    {
      enableHighAccuracy: true,
      maximumAge: 10000, // aceita posição de até 10s atrás — reduz chamadas redundantes ao GPS
      timeout: 5000      // falha rápido se o GPS não responder
    }
  );
}

function stopTracking(buttonElement) {
  if (watchId !== null) {
    navigator.geolocation.clearWatch(watchId);
    watchId = null;
  }
  isTracking = false;
  lastLat = null;
  lastLng = null;
  nativeLocationCallback = null;
  if (buttonElement) buttonElement.classList.remove("active-tracking");
  console.log("🛑 Rastreamento contínuo parado.");

  if (window.webkit?.messageHandlers?.locationHandler) {
    window.webkit.messageHandlers.locationHandler.postMessage('stopTracking');
  }
}

export function isCurrentlyTracking() {
  return isTracking;
}

// Ponte nativa iOS (Swift → JS): chamada pela WebView quando o app envia posição em background.
// Aplica o mesmo filtro de ruído do watchPosition para evitar updates desnecessários.
window.handleNativeLocationUpdate = (latitude, longitude) => {
  const lat = parseFloat(latitude);
  const lng = parseFloat(longitude);
  if (isNaN(lat) || isNaN(lng)) return;

  if (lastLat !== null) {
    const dist = haversineMeters(lastLat, lastLng, lat, lng);
    if (dist < MIN_MOVE_METERS) return;
    console.log(`🌐 [Native] Movimento: ${dist.toFixed(1)}m → (${lat.toFixed(6)}, ${lng.toFixed(6)})`);
  } else {
    console.log(`🌐 [Native] Posição inicial: (${lat.toFixed(6)}, ${lng.toFixed(6)})`);
  }

  lastLat = lat;
  lastLng = lng;

  if (nativeLocationCallback) nativeLocationCallback(lat, lng);

  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
  fetch('/users/update_location', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken || ''
    },
    body: JSON.stringify({ latitude: lat, longitude: lng })
  }).catch(err => console.warn('⚠️ [Native] Falha ao enviar localização:', err));
};
