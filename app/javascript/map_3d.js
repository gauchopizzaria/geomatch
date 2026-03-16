
import { toggleLiveTracking, isCurrentlyTracking } from "./live_location";
// Turf.js é esperado estar disponível globalmente (ex: via CDN)
// import * as turf from '@turf/turf'; // Removido para evitar erro de build se não instalado


// --- Configurações e Estado Global ---
const INITIAL_RANGE_METERS = 150;
const FETCH_COOLDOWN_MS = 10000;
const STORAGE_KEYS = {
  RANGE: "geomatch_range",
  GENDER_FILTER: "geomatch_gender_filter",
  INVISIBLE_MODE: "geomatch_invisible_mode",
};

let map;
let fixedUserLat = null;
let fixedUserLng = null;
let currentRangeMeters = parseInt(localStorage.getItem(STORAGE_KEYS.RANGE)) || INITIAL_RANGE_METERS;
let currentGenderFilter = localStorage.getItem(STORAGE_KEYS.GENDER_FILTER) || "all";
let mapboxUserMarkers = {}; // Para gerenciar marcadores de usuários no Mapbox
let lastUserFetchTime = 0;
let isUserInvisible = false;

const radarSourceId = 'radar-circle-source';
const radarLayerId = 'radar-circle-layer';

// --- Funções de Interface (UI) ---

// Função para exibir mensagens rápidas (Toasts)
function showQuickMessage(text) {
  let toast = document.getElementById("gender-toast");
  if (!toast) {
    toast = document.createElement("div");
    toast.id = "gender-toast";
    document.body.appendChild(toast);
  }
  toast.textContent = text;
  toast.classList.add("show");
  setTimeout(() => {
    toast.classList.remove("show");
  }, 2000);
}

function showTrackingToast(text) {
  let toast = document.getElementById("tracking-toast");
  if (!toast) {
    toast = document.createElement("div");
    toast.id = "tracking-toast";
    document.body.appendChild(toast);
  }
  toast.textContent = text;
  toast.classList.remove("show");
  setTimeout(() => {
    toast.classList.add("show");
  }, 10);
  if (window.trackingToastTimer) clearTimeout(window.trackingToastTimer);
  window.trackingToastTimer = setTimeout(() => {
    toast.classList.remove("show");
  }, 3000);
}

function showLoadingAnimation() {
  const usersList = document.getElementById("users-list");
  const usersCountElement = document.getElementById("nearby-count");
  if (usersList) {
    usersList.innerHTML = `
      <li class="loading-skeleton"><div class="skeleton-avatar"></div><div class="skeleton-text"><div class="skeleton-line"></div></div></li>
      <li class="loading-skeleton"><div class="skeleton-avatar"></div><div class="skeleton-text"><div class="skeleton-line"></div></div></li>
    `;
  }
  if (usersCountElement) usersCountElement.textContent = "...";
}

function hideLoadingAnimation() {
  // Implementação pode ser vazia ou remover skeletons
}

function closeUserPopup() {
  const popup = document.getElementById("user-popup");
  if (popup) {
    popup.classList.add("hidden");
    popup.classList.remove("show");
    const content = popup.querySelector(".popup-content-fullscreen");
    if(content) content.classList.remove("expanded");
    const rejectInput = document.getElementById("popup-reject-input");
    const likeInput = document.getElementById("popup-like-input");
    if(rejectInput) rejectInput.value = "";
    if(likeInput) likeInput.value = "";
  }
}

// --- Funções de Mapa e Dados ---

function updateRadarVisuals() {
  const container = document.querySelector(".discover-fullscreen-container");
  if (!map || !fixedUserLat || !container) return;

  // 1. Posicionamento do Spotlight (CSS)
  const point = map.project([fixedUserLng, fixedUserLat]);
  container.style.setProperty('--radar-x', `${point.x}px`);
  container.style.setProperty('--radar-y', `${point.y}px`);

  // 2. Escala do Raio (CSS)
  const zoom = map.getZoom();
  // A conversão de metros para pixels no Mapbox é mais complexa e geralmente não é feita diretamente para CSS como no Leaflet.
  // Em vez disso, o círculo geográfico é o principal indicador de raio.
  // Manteremos a variável CSS para compatibilidade, mas seu efeito visual pode ser diferente.
  const metersPerPixel = 156543.03392 * Math.abs(Math.cos(fixedUserLat * Math.PI / 180)) / Math.pow(2, zoom);
  const radiusInPixels = currentRangeMeters / metersPerPixel;
  container.style.setProperty('--radar-radius', `${radiusInPixels}px`);

  // 3. Círculo Geográfico (Turf.js no Mapbox)
  if (map.isStyleLoaded()) {
    const center = [fixedUserLng, fixedUserLat];
    const circle = turf.circle(center, currentRangeMeters / 1000, { steps: 64, units: 'kilometers' }); // Assume turf global

    if (map.getSource(radarSourceId)) {
      map.getSource(radarSourceId).setData(circle);
    } else {
      map.addSource(radarSourceId, { 'type': 'geojson', 'data': circle });
      map.addLayer({
        'id': radarLayerId,
        'type': 'fill',
        'source': radarSourceId,
        'paint': { 'fill-color': '#F4E4BC', 'fill-opacity': 0.1 }
      }); // Adiciona a camada do radar sem depender de uma camada específica para posicionamento.
    }
  }
}

async function loadNearbyUsers(latitude, longitude, rangeMeters, genderFilter) {
  showLoadingAnimation();
  const usersList = document.getElementById("users-list");
  const usersCountElement = document.getElementById("nearby-count");
  const assetsData = document.getElementById('assets-data');
  const frameUrl = assetsData ? assetsData.dataset.frameUrl : '';

  try {
    let url = `/users/nearby?latitude=${latitude}&longitude=${longitude}&range=${rangeMeters}`;
    if (genderFilter !== "all") url += `&gender=${genderFilter}`;

    const response = await fetch(url);
    if (!response.ok) throw new Error("Falha na rede");
    const users = await response.json();

    // Limpa marcadores antigos
    Object.values(mapboxUserMarkers).forEach(m => m.remove());
    mapboxUserMarkers = {};
    if (usersList) usersList.innerHTML = "";

    if (users.length === 0) {
      if (usersList) usersList.innerHTML = '<li class="text-center loading-text">Ninguém por perto...</li>';
      if (usersCountElement) usersCountElement.textContent = "0";
      hideLoadingAnimation();
      return;
    }

    users.forEach(user => {
      const distDisplay = (user.distance_km || user.distance || 0);

      const avatarHtml = `
        <div class="avatar-frame-wrapper">
          <img src="${user.avatar_url || '/default-avatar.png'}" class="avatar-user-img">
          <img src="${frameUrl}" class="avatar-frame-overlay">
        </div>
      `;

      let uLat = parseFloat(user.latitude);
      let uLng = parseFloat(user.longitude);

      // Adiciona jitter para evitar marcadores sobrepostos
      const jitter = () => (Math.random() - 0.5) * 0.0005;
      uLat += jitter();
      uLng += jitter();

      if (!isNaN(uLat) && !isNaN(uLng)) {
        const el = document.createElement('div');
        el.className = 'custom-marker';
        el.innerHTML = avatarHtml;

        const marker = new mapboxgl.Marker(el)
          .setLngLat([uLng, uLat])
          .addTo(map);
        mapboxUserMarkers[user.id] = marker;
        el.onclick = () => showUserPopup(user);
      }

      // Adiciona na lista
      if (usersList) {
        const isOnline = user.online;
        const li = document.createElement("li");
        li.className = "user-list-item";
        li.innerHTML = `
          ${avatarHtml}
          <div class="user-list-info">
              <div class="user-list-name-row" style="display: flex; align-items: center; gap: 5px;">
                  <span class="user-list-name">${user.username || user.display_name || 'Usuário'}</span>
                  <span class="header-status" style="font-size: 0.7rem;">
                      <span class="${isOnline ? 'dot-online' : 'dot-offline'}">●</span>
                      ${isOnline ? 'Online' : 'Offline'}
                  </span>
              </div>
              <div class="user-list-distance">${distDisplay} km</div>
          </div>
        `;
        li.addEventListener("click", () => {
          if (!isNaN(uLat) && !isNaN(uLng)) {
            map.flyTo({ center: [uLng, uLat], zoom: 16 });
            showUserPopup(user);
          }
        });
        usersList.appendChild(li);
      }
    });

    if (usersCountElement) usersCountElement.textContent = users.length;
    hideLoadingAnimation();
  } catch (error) {
    console.error("Erro ao carregar usuários próximos:", error);
    hideLoadingAnimation();
    if (usersList) usersList.innerHTML = '<li class="text-center loading-text">Erro ao carregar usuários.</li>';
  }
}

function showUserPopup(user) {
  console.log("Dados do usuário recebidos:", user);
  const userPopup = document.getElementById("user-popup");
  if (!userPopup) return;

  userPopup.dataset.userId = user.id;

  const img = userPopup.querySelector("#popup-avatar");
  if(img) img.src = user.avatar_url || "/default-avatar.png";
  
  const name = userPopup.querySelector("#popup-username");
  if(name) name.textContent = user.username || user.display_name || "Usuário";
  
  const loc = userPopup.querySelector("#popup-location");
  if(loc) loc.textContent = user.city || "Localização desconhecida";
  
  const distBadge = userPopup.querySelector("#popup-distance");
  const distVal = user.distance_km || user.distance;
  if(distBadge) distBadge.textContent = distVal ? `${distVal} km` : "";

  const bio = userPopup.querySelector("#popup-bio");
  if(bio) bio.textContent = user.bio || "Não informado!";

  const genderElement = userPopup.querySelector("#popup-gender");
  if (genderElement) {
    const genderValue = user.gender ? user.gender.toLowerCase() : "";
    let genderText = "Não informado";
    if (genderValue === 'homem' || genderValue === 'male') {
      genderText = 'Masculino';
    } else if (genderValue === 'mulher' || genderValue === 'female') {
      genderText = 'Feminino';
    } else if (genderValue === 'não binário' || genderValue === 'nao binario' || genderValue === 'non-binary') {
      genderText = 'Não Binário';
    } else if (genderValue === 'nao-dizer') {
      genderText = 'Prefere não dizer';
    }
    genderElement.textContent = genderText;
  }

  const interest = userPopup.querySelector("#popup-interest");
  if(interest) interest.textContent = user.interested_in ? `Busca: ${user.interested_in}` : "Busca: Todos";

  const tagsContainer = userPopup.querySelector("#popup-tags-container");
  const tagsList = userPopup.querySelector("#popup-tags-list");
  
  if(tagsList) {
      tagsList.innerHTML = ""; 
      if (user.hobbies_list && Array.isArray(user.hobbies_list) && user.hobbies_list.length > 0) {
          tagsContainer.style.display = "block";
          user.hobbies_list.forEach(tag => {
              const span = document.createElement("span");
              span.className = "tag-pill";
              span.textContent = tag;
              tagsList.appendChild(span);
          });
      } else {
          tagsContainer.style.display = "none";
      }
  }

  const content = userPopup.querySelector(".popup-content-fullscreen");
  if(content) content.classList.remove("expanded");

  const forms = [
      document.getElementById("popup-reject-form"),
      document.getElementById("popup-chat-form"),
      document.getElementById("popup-like-form")
  ];

  forms.forEach(form => {
        if (form) {
          let baseUrl = form.getAttribute("data-base-action");
          if (!baseUrl) { baseUrl = form.action; form.setAttribute("data-base-action", baseUrl); }
          const newUrl = baseUrl.replace(/\/0\/?(\?.*)?$/, '/' + user.id + '$1');
          if (newUrl.includes("user_id=")) {
              form.action = newUrl.replace("user_id=0", `user_id=${user.id}`);
          } else {
              form.action = newUrl;
          }
        }
  });

  userPopup.classList.remove("hidden");
  userPopup.classList.add("show");
}

function initializeMapAndLocation() {
  const mapboxToken = document.querySelector('meta[name="mapbox-token"]').content;
  mapboxgl.accessToken = mapboxToken;

  const mapElement = document.getElementById('map-3d');
  if (!mapElement) return;

  map = new mapboxgl.Map({
    container: 'map-3d',
    style: 'mapbox://styles/mapbox/standard',
    center: [-39.2781, -14.7876], // Default center
    zoom: 16.5,
    pitch: 75,
    bearing: -20,
    antialias: true
  });

  map.on('style.load', () => {
    map.setConfigProperty('basemap', 'show3dObjects', true);
    map.setConfigProperty('basemap', 'show3dTrees', true);
    map.setConfigProperty('basemap', 'lightPreset', 'day');
    
    map.addSource('mapbox-dem', {
      'type': 'raster-dem',
      'url': 'mapbox://mapbox.mapbox-terrain-dem-v1',
      'tileSize': 512,
      'maxzoom': 14
    });
    map.setTerrain({ 'source': 'mapbox-dem', 'exaggeration': 1.5 });
    map.setFog({
      'range': [0.5, 10],
      'color': '#f8f0e3',
      'horizon-blend': 0.1
    });
    map.setPaintProperty('landuse', 'fill-color', '#e8f5e9');

    // Tenta obter a localização atual do usuário
    if ("geolocation" in navigator) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          fixedUserLat = position.coords.latitude;
          fixedUserLng = position.coords.longitude;
          map.flyTo({ center: [fixedUserLng, fixedUserLat], zoom: 16.5, essential: true });
          updateRadarVisuals();
          loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
        },
        (error) => {
          console.warn("⚠️ Erro ao obter localização:", error.message);
          // Fallback para localização padrão se não conseguir o GPS
          fixedUserLat = -14.2350;
          fixedUserLng = -51.9253;
          map.flyTo({ center: [fixedUserLng, fixedUserLat], zoom: 16.5, essential: true });
          updateRadarVisuals();
          loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
          if (error.code === 1) {
            alert("O GeoMatch precisa da sua localização para funcionar. Por favor, verifique as permissões do seu navegador/celular.");
          }
        },
        {
          enableHighAccuracy: true,
          maximumAge: 0,
          timeout: 10000
        }
      );
    } else {
      // Fallback para localização padrão se a geolocalização não for suportada
      fixedUserLat = -14.2350;
      fixedUserLng = -51.9253;
      map.flyTo({ center: [fixedUserLng, fixedUserLat], zoom: 16.5, essential: true });
      updateRadarVisuals();
      loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
    }
  });

  map.on('move', updateRadarVisuals);
  map.on('zoom', updateRadarVisuals);
}

// --- Event Listeners e Inicialização ---

document.addEventListener("turbo:load", () => {
  initializeMapAndLocation();

  const rangeSlider = document.getElementById("radar-range");
  const rangeValueText = document.getElementById("range-value-text");
  const radarControl = document.querySelector('.radar-control-floating');
  const containerElement = document.querySelector('.discover-fullscreen-container');
  const fabCenterMap = document.getElementById("fab-center-map");
  const toggleVisibilityBtn = document.getElementById("toggle-visibility-btn");
  const genderToggleBtn = document.getElementById("gender-filter-toggle");
  const fabLiveTracking = document.getElementById("fab-live-tracking");
  const closePopupBtn = document.getElementById("close-popup-btn");
  const popupOverlay = document.querySelector(".popup-overlay");
  const userPopup = document.getElementById("user-popup");

  // SLIDER DE RAIO
  if (rangeSlider && rangeValueText) {
    const updateSliderVisuals = (val) => {
      rangeValueText.textContent = `${val}m`;
      const max = rangeSlider.max || 300;
      const percent = (val / max) * 100;
      rangeSlider.style.backgroundImage = `linear-gradient(to right, #f4e4bc 0%, #f4e4bc ${percent}%, transparent ${percent}%, transparent 100%)`;
      updateRadarVisuals();
    };

    rangeSlider.value = currentRangeMeters;
    updateSliderVisuals(currentRangeMeters);
    
    rangeSlider.addEventListener("input", (e) => {
      const val = parseInt(e.target.value, 10);
      currentRangeMeters = val;
      updateSliderVisuals(val);
    });
    
    rangeSlider.addEventListener("change", () => {
      localStorage.setItem(STORAGE_KEYS.RANGE, currentRangeMeters);
      if (fixedUserLat && fixedUserLng) {
        loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
      }
    });
  }

  // RADAR DRAGGABLE
  if (radarControl) {
    let isDragging = false;
    let startX, startY, initialLeft, initialTop;
    const dragStart = (e) => {
      if (e.target.tagName.toLowerCase() === 'input') return;
      isDragging = true;
      const clientX = e.touches ? e.touches[0].clientX : e.clientX;
      const clientY = e.touches ? e.touches[0].clientY : e.clientY;
      startX = clientX;
      startY = clientY;
      const style = window.getComputedStyle(radarControl);
      initialLeft = parseInt(style.left, 10) || 0;
      initialTop = parseInt(style.top, 10) || 0;
    };
    const dragMove = (e) => {
      if (!isDragging) return;
      e.preventDefault();
      const clientX = e.touches ? e.touches[0].clientX : e.clientX;
      const clientY = e.touches ? e.touches[0].clientY : e.clientY;
      const deltaX = clientX - startX;
      const deltaY = clientY - startY;
      radarControl.style.left = `${initialLeft + deltaX}px`;
      radarControl.style.top = `${initialTop + deltaY}px`;
    };
    const dragEnd = () => { isDragging = false; };
    radarControl.addEventListener('mousedown', dragStart);
    window.addEventListener('mousemove', dragMove);
    window.addEventListener('mouseup', dragEnd);
    radarControl.addEventListener('touchstart', dragStart, { passive: false });
    window.addEventListener('touchmove', dragMove, { passive: false });
    window.addEventListener('touchend', dragEnd);
  }

  // FILTRO GÊNERO
  if (genderToggleBtn) {
    genderToggleBtn.addEventListener("click", () => {
      let message = "";
      if (currentGenderFilter === "all") {
        currentGenderFilter = "male";
        message = "Exibindo apenas: Homens";
      } else if (currentGenderFilter === "male") {
        currentGenderFilter = "female";
        message = "Exibindo apenas: Mulheres";
      } else if (currentGenderFilter === "female") {
        currentGenderFilter = "non-binary";
        message = "Exibindo apenas: Não Binários";
      } else {
        currentGenderFilter = "all";
        message = "Exibindo: Todos";
      }
      localStorage.setItem(STORAGE_KEYS.GENDER_FILTER, currentGenderFilter);
      showQuickMessage(message);
      genderToggleBtn.style.transform = "scale(0.8)";
      setTimeout(() => {
        genderToggleBtn.style.transform = "scale(1)";
        if (fixedUserLat && fixedUserLng) {
          showLoadingAnimation();
          loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
        }
      }, 150);
    });
  }

  // BOTTOM SHEET
  const bottomSheet = document.querySelector(".users-bottom-sheet");
  const handle = document.querySelector(".bottom-sheet-handle");
  if (bottomSheet && handle) {
    let startY = 0; let startHeight = 0; let isDraggingSheet = false;
    let startVh = 0;
    const SNAP_MIN = 25; const SNAP_MAX = 85; const SNAP_THRESHOLD = 50;
    const onDragStart = (e) => {
      isDraggingSheet = true;
      bottomSheet.classList.add("dragging");
      startY = e.touches ? e.touches[0].clientY : e.clientY;
      startHeight = bottomSheet.getBoundingClientRect().height;
      startVh = (startHeight / window.innerHeight) * 100;
    };
    const onDragMove = (e) => {
      if (!isDraggingSheet) return;
      e.preventDefault();
      const currentY = e.touches ? e.touches[0].clientY : e.clientY;
      const deltaY = startY - currentY;
      let newHeight = startHeight + deltaY;
      const minH = window.innerHeight * (SNAP_MIN / 100);
      const maxH = window.innerHeight * (SNAP_MAX / 100);
      if (newHeight < minH) newHeight = minH + (newHeight - minH) * 0.2;
      if (newHeight > maxH) newHeight = maxH + (newHeight - maxH) * 0.2;
      bottomSheet.style.height = `${newHeight}px`;
    };
    const onDragEnd = () => {
      if (!isDraggingSheet) return;
      isDraggingSheet = false;
      bottomSheet.classList.remove("dragging");
      const currentHeight = bottomSheet.getBoundingClientRect().height;
      const viewportHeight = window.innerHeight;
      const currentVh = (currentHeight / viewportHeight) * 100;
      const diff = currentVh - startVh;
      if (currentVh > 40) {
        bottomSheet.style.height = `${SNAP_MAX}vh`;
      } else {
        bottomSheet.style.height = `${SNAP_MIN}vh`;
      }
    };
    handle.addEventListener("mousedown", onDragStart);
    handle.addEventListener("touchstart", onDragStart, { passive: false });
    window.addEventListener("mousemove", onDragMove);
    window.addEventListener("touchmove", onDragMove, { passive: false });
    window.addEventListener("mouseup", onDragEnd);
    window.addEventListener("touchend", onDragEnd);
  }

  // BOTÃO CENTRALIZAR MAPA
  if (fabCenterMap) {
    fabCenterMap.addEventListener("click", () => {
      console.log("Centralizar mapa clicado");
      if (fixedUserLat && fixedUserLng) {
        map.flyTo({ center: [fixedUserLng, fixedUserLat], zoom: 16.5, essential: true });
      } else {
        // Fallback se ainda não pegou o GPS
        map.flyTo({ center: [-39.2781, -14.7876], zoom: 16.5, essential: true });
      }
    });
  }

  // MODO TEMPO REAL (FOLLOW ME)
  if (fabLiveTracking) {
    fabLiveTracking.addEventListener("click", () => {
      const isNowTracking = toggleLiveTracking(map, fabLiveTracking, (newLat, newLng) => {
        fixedUserLat = newLat;
        fixedUserLng = newLng;
        updateRadarVisuals();
        // Não há addUserMarker separado para o usuário no Mapbox GL JS, ele é o centro do radar
        const now = Date.now();
        if (now - lastUserFetchTime > FETCH_COOLDOWN_MS) {
          lastUserFetchTime = now;
          loadNearbyUsers(newLat, newLng, currentRangeMeters, currentGenderFilter);
          if (!isUserInvisible) {
            fetch(`/users/update_location?latitude=${newLat}&longitude=${newLng}`, {
              method: 'POST',
              headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content }
            });
          }
        }
      });

      const metaUserId = document.querySelector('meta[name="current-user-id"]');
      const userId = metaUserId ? metaUserId.content : null;

      if (isNowTracking) {
        showTrackingToast("✅ Visibilidade em tempo real ligada! Prepare-se para encontros espontâneos.");
        if (window.Android && userId) {
           console.log("Ativando rastreio nativo em 2º plano para o utilizador: " + userId);
           window.Android.iniciarRastreioSegundoPlano(userId);
        } else {
           console.log("Não está no Android ou o ID do utilizador não foi encontrado.");
        }
      } else {
        showTrackingToast("❌ Visibilidade em tempo real desativada. Sua localização não está mais visível.");
        if (window.Android) {
           console.log("Desativando rastreio nativo em 2º plano.");
           window.Android.pararRastreioSegundoPlano();
        }
      }
    });
  }

  // MODO INVISÍVEL
  if (toggleVisibilityBtn) {
    const eyeOpen = toggleVisibilityBtn.querySelector(".eye-open");
    const eyeClosed = toggleVisibilityBtn.querySelector(".eye-closed");

    const updateVisibilityUI = (isInvisible) => {
      isUserInvisible = isInvisible;
      if (isInvisible) {
        toggleVisibilityBtn.classList.add("active");
        toggleVisibilityBtn.classList.add("invisible-mode");
        if (eyeOpen) eyeOpen.classList.add("hidden");
        if (eyeClosed) eyeClosed.classList.remove("hidden");
      } else {
        toggleVisibilityBtn.classList.remove("active");
        toggleVisibilityBtn.classList.remove("invisible-mode");
        if (eyeOpen) eyeOpen.classList.remove("hidden");
        if (eyeClosed) eyeClosed.classList.add("hidden");
      }
    };

    const userData = document.getElementById('current-user-data');
    const initialInvisible = userData ? (userData.dataset.invisible === 'true') : false;
    updateVisibilityUI(initialInvisible);

    toggleVisibilityBtn.addEventListener("click", async () => {
      console.log("Botão Invisibilidade clicado");
      try {
        const token = document.querySelector('meta[name="csrf-token"]').content;
        const response = await fetch('/users/toggle_visibility', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': token
          }
        });

        if (response.status === 403) {
          console.log("Status 403: Upgrade necessário");
          const data = await response.json();
          if (data.upgrade_required) {
            const modalResponse = await fetch('/plans/modal?type=invisible');
            const modalHtml = await modalResponse.text();
            const container = document.getElementById("upgrade-modal-container");
            container.innerHTML = modalHtml;
            const backdrop = container.querySelector(".upgrade-modal-backdrop");
            const fecharModalGeoMatch = () => {
              if (backdrop) {
                backdrop.style.opacity = '0';
                setTimeout(() => {
                  container.innerHTML = "";
                }, 300);
              }
            };
            container.querySelectorAll(".close-modal-btn").forEach(btn => {
              btn.onclick = (e) => {
                e.preventDefault();
                fecharModalGeoMatch();
              };
            });
            if (backdrop) {
              backdrop.onclick = (e) => {
                if (e.target === backdrop) fecharModalGeoMatch();
              };
            }
          }
          return;
        }

        if (!response.ok) throw new Error("Erro ao salvar no servidor");

        const data = await response.json();
        console.log("Sucesso! Novo estado:", data.invisible);
        updateVisibilityUI(data.invisible);

      } catch (error) {
        console.error("Erro ao alternar visibilidade:", error);
      }
    });
  }

  // FECHAR POPUP APÓS AÇÃO (Like/Reject)
  document.addEventListener("turbo:submit-end", (e) => {
    const formId = e.target.id;
    if (formId === "popup-like-form" || formId === "popup-reject-form") {
      if (e.detail.success) {
        closeUserPopup();
      }
    }
  });

  // FUNÇÃO GLOBAL DE FECHAR POPUP
  if (closePopupBtn) {
    const newBtn = closePopupBtn.cloneNode(true);
    closePopupBtn.parentNode.replaceChild(newBtn, closePopupBtn);
    newBtn.addEventListener("click", (e) => {
      e.preventDefault();
      console.log("Botão fechar clicado");
      closeUserPopup();
    });
  }

  if (popupOverlay) {
    popupOverlay.addEventListener("click", (e) => {
      console.log("Fundo clicado");
      closeUserPopup();
    });
  }

  // DRAG / SWIPE NO POPUP
  const popupContent = document.querySelector(".popup-content-fullscreen");
  const popupHandle = document.querySelector(".popup-drag-handle-area");
  
  if (popupContent) {
      let startY = 0;
      let currentY = 0;
      let isDragging = false;
      let startHeight = 0;
      const THRESHOLD = 100;

      const isExpanded = () => popupContent.classList.contains("expanded");

      const onTouchStart = (e) => {
          const detailsContainer = document.getElementById("popup-full-details");
          const scrollTop = detailsContainer ? detailsContainer.scrollTop : 0;

          if (isExpanded() && scrollTop > 0 && !popupHandle.contains(e.target)) {
              return; 
          }

          isDragging = true;
          startY = e.touches[0].clientY;
          startHeight = popupContent.offsetHeight;
          popupContent.style.transition = "none";
      };

      const onTouchMove = (e) => {
          if (!isDragging) return;
          
          currentY = e.touches[0].clientY;
          const deltaY = startY - currentY; 

          if (!isExpanded() && deltaY > 0) {
               e.preventDefault();
               popupContent.style.height = `${startHeight + deltaY}px`;
          } 
          else if (isExpanded() && deltaY < 0) {
               const detailsContainer = document.getElementById("popup-full-details");
               if (!detailsContainer || detailsContainer.scrollTop <= 0) {
                   e.preventDefault();
                   popupContent.style.height = `${startHeight + deltaY}px`;
               }
          }
      };

      const onTouchEnd = (e) => {
          if (!isDragging) return;
          isDragging = false;
          popupContent.style.transition = "height 0.3s cubic-bezier(0.25, 1, 0.5, 1)";
          popupContent.style.height = ""; 

          const deltaY = startY - currentY;

          if (!isExpanded()) {
              if (deltaY > THRESHOLD) {
                  popupContent.classList.add("expanded");
              }
          } else {
              if (deltaY < -THRESHOLD) {
                  popupContent.classList.remove("expanded");
              }
          }
      };

      popupContent.addEventListener("touchstart", onTouchStart, { passive: false });
      popupContent.addEventListener("touchmove", onTouchMove, { passive: false });
      popupContent.addEventListener("touchend", onTouchEnd);
  }

  // Envia um sinal de "estou aqui" a cada 2 minutos
  setInterval(() => {
    if (fixedUserLat && fixedUserLng && !isUserInvisible) {
      fetch(`/users/update_location?latitude=${fixedUserLat}&longitude=${fixedUserLng}`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      });
    }
  }, 120000); // 120.000 ms = 2 minutos

  // Ativa rastreamento automático na entrada da tela
  setTimeout(() => {
    if (fabLiveTracking) {
      fabLiveTracking.click();
      console.log("Rastreamento automático ativado na entrada da tela.");
    }
  }, 1000); // 1 segundo de delay

  // Chama toda vez que o usuário voltar para a aba/app (Sair e Entrar)
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      console.log("👁️ Usuário voltou para o app. Atualizando GPS...");
      // Força a atualização da localização e recarrega usuários
      if ("geolocation" in navigator) {
        navigator.geolocation.getCurrentPosition(
          (position) => {
            fixedUserLat = position.coords.latitude;
            fixedUserLng = position.coords.longitude;
            updateRadarVisuals();
            loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
          },
          (error) => {
            console.warn("⚠️ Erro ao obter localização ao retornar:", error.message);
          },
          {
            enableHighAccuracy: true,
            maximumAge: 0,
            timeout: 10000
          }
        );
      }
    }
  });

  // Adiciona estilos CSS dinamicamente
  const style = document.createElement("style");
  style.textContent = `
    .user-location-marker { position: relative; width: 40px; height: 40px; }
    .user-location-dot { width: 12px; height: 12px; background: #ccc099; border-radius: 50%; border: 2px solid #fff; position: relative; z-index: 10; top: 14px; left: 14px; }
    .user-location-pulse { position: absolute; width: 40px; height: 40px; border-radius: 50%; border: 2px solid rgba(212, 175, 55, 0.5); animation: pulse 2s infinite; }
    @keyframes pulse { 0% { transform: scale(0.5); opacity: 1; } 100% { transform: scale(1.5); opacity: 0; } }
    .loading-skeleton { display: flex; gap: 10px; padding: 10px; background: #252527; border-radius: 8px; margin-bottom: 5px; }
    .skeleton-avatar { width: 40px; height: 40px; background: #444; border-radius: 50%; }
    .skeleton-text { flex: 1; display: flex; flex-direction: column; gap: 5px; justify-content: center; }
    .skeleton-line { height: 10px; background: #444; border-radius: 4px; width: 80%; }
    .users-bottom-sheet {
      transition: height 0.4s cubic-bezier(0.25, 1, 0.5, 1); /* Transição suave */
      will-change: height;
    }
    .users-bottom-sheet.dragging {
      transition: none; /* Remove a transição enquanto arrasta para não dar lag */
    }
  `;
  document.head.appendChild(style);
});
