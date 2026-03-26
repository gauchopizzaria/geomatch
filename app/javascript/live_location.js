let watchId = null;
let isTracking = false;
let lastLoggedState = null;

// Função para iniciar ou parar o rastreamento
export function toggleLiveTracking(map, buttonElement, onLocationChange) {
  if (isTracking) {
    stopTracking(buttonElement);
    return false;
  } else {
    startTracking(map, buttonElement, onLocationChange);
    return true;
  }
}

function startTracking(map, buttonElement, onLocationChange) {
  if (!("geolocation" in navigator)) {
    alert("Geolocalização não suportada pelo seu navegador.");
    return;
  }

  isTracking = true;
  if (buttonElement) buttonElement.classList.add("active-tracking");

  if (lastLoggedState !== true) {
    console.log("📍 Iniciando rastreamento contínuo...");
    lastLoggedState = true;
  }

  // watchPosition é o segredo para atualizar em tempo real
  watchId = navigator.geolocation.watchPosition(
    (position) => {
      const lat = position.coords.latitude;
      const lng = position.coords.longitude;
      
      console.log(`🚶 Movimento detectado: ${lat}, ${lng}`);

          // Move a câmera do mapa suavemente para a nova localização
      // Adaptação para Mapbox GL JS ou Leaflet
      if (map.getCenter && map.setCenter) { // É um mapa Mapbox GL JS
        map.panTo([lng, lat], { duration: 1000 }); // Mapbox usa [lng, lat]
      } else if (map.setView) { // É um mapa Leaflet
        map.panTo([lat, lng], { animate: true, duration: 1.0 }); // Leaflet usa [lat, lng]
      }

      // Chama a função de callback no map.js para atualizar marcadores e buscar usuários
      if (onLocationChange) onLocationChange(lat, lng);
    },
    (error) => {
      console.warn("⚠️ Erro no rastreamento contínuo:", error.message);
      stopTracking(buttonElement);
    },
    {
      enableHighAccuracy: true, // Força o uso do GPS (melhor precisão)
      maximumAge: 0,            // Não aceita posições velhas
      timeout: 10000            // Tempo limite de busca
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

  if (lastLoggedState !== false) {
    console.log("🛑 Rastreamento contínuo parado.");
    lastLoggedState = false;
  }
}

// Verifica se o rastreamento está ativo
export function isCurrentlyTracking() {
  return isTracking;
}