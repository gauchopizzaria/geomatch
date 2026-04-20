let watchId = null;
let isTracking = false;

// Inicia rastreamento direto — sempre liga, independente do estado anterior.
// Usar na inicialização da tela para garantir que o GPS começa ligado.
export function startLiveTracking(map, buttonElement, onLocationChange) {
  if (watchId !== null) {
    navigator.geolocation.clearWatch(watchId);
    watchId = null;
  }
  isTracking = false;
  startTracking(map, buttonElement, onLocationChange);
}

// Alterna entre ligado/desligado — usar no evento de click do botão.
export function toggleLiveTracking(map, buttonElement, onLocationChange) {
  if (isTracking) {
    stopTracking(buttonElement);
    return false;
  } else {
    startTracking(map, buttonElement, onLocationChange);
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
  if (buttonElement) buttonElement.classList.remove("active-tracking");
}

function startTracking(map, buttonElement, onLocationChange) {
  if (!("geolocation" in navigator)) {
    alert("Geolocalização não suportada pelo seu navegador.");
    return;
  }

  isTracking = true;
  if (buttonElement) buttonElement.classList.add("active-tracking");
  console.log("📍 Iniciando rastreamento contínuo...");

  watchId = navigator.geolocation.watchPosition(
    (position) => {
      const lat = position.coords.latitude;
      const lng = position.coords.longitude;
      console.log(`🚶 Movimento detectado: ${lat}, ${lng}`);

      if (map.getCenter && map.setCenter) {
        map.panTo([lng, lat], { duration: 1000 });
      } else if (map.setView) {
        map.panTo([lat, lng], { animate: true, duration: 1.0 });
      }

      if (onLocationChange) onLocationChange(lat, lng);
    },
    (error) => {
      console.warn("⚠️ Erro no rastreamento contínuo:", error.message);
      stopTracking(buttonElement);
    },
    {
      enableHighAccuracy: true,
      maximumAge: 0,
      timeout: 10000
    }
  );
}

function stopTracking(buttonElement) {
  if (watchId !== null) {
    navigator.geolocation.clearWatch(watchId);
    watchId = null;
  }
  isTracking = false;
  if (buttonElement) buttonElement.classList.remove("active-tracking");
  console.log("🛑 Rastreamento contínuo parado.");
}

export function isCurrentlyTracking() {
  return isTracking;
}