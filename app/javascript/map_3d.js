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
let rotationAnimId = null;
let rotationTimer = null;
let isCinematicMode = false;
let cinematicPopup = null;
let activeMarkerEl = null;

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

// --- Funções Cinematográficas ---

function stopRotation() {
  if (rotationAnimId) { cancelAnimationFrame(rotationAnimId); rotationAnimId = null; }
  if (rotationTimer) { clearTimeout(rotationTimer); rotationTimer = null; }
}

function startTimedRotation(onComplete) {
  stopRotation();
  const startBearing = map.getBearing();
  const startTime = performance.now();
  const DURATION = 30000;

  function rotate(now) {
    const elapsed = now - startTime;
    if (elapsed >= DURATION) {
      rotationAnimId = null;
      if (isCinematicMode && onComplete) onComplete();
      return;
    }
    const progress = elapsed / DURATION;
    // Curva de seno: mais suave que quadrática em movimentos longos
    const easedProgress = -(Math.cos(Math.PI * progress) - 1) / 2;
    map.setBearing(startBearing + 360 * easedProgress);
    rotationAnimId = requestAnimationFrame(rotate);
  }

  rotationAnimId = requestAnimationFrame(rotate);
}

function resetCamera() {
  stopRotation();
  isCinematicMode = false;
  document.body.classList.remove('cinematic-mode');
  map.easeTo({ pitch: 0, bearing: 0, duration: 800, easing: t => t });
}

function openCinematicPopup(user, lngLat) {
  if (cinematicPopup) { cinematicPopup.remove(); cinematicPopup = null; }
  const distVal = user.distance_km || user.distance;
  const distText = distVal ? `a ${distVal} km` : '';
  const nameAge = user.age
    ? `${user.username || user.display_name || 'Usuário'}, ${user.age}`
    : (user.username || user.display_name || 'Usuário');
  cinematicPopup = new mapboxgl.Popup({
    closeButton: false,
    closeOnClick: false,
    className: 'cinematic-popup',
    offset: 32,
    anchor: 'left',
    maxWidth: '210px'
  })
    .setLngLat(lngLat)
    .setHTML(`
      <div class="cp-mini-card">
        <img src="${user.avatar_url || '/default-avatar.png'}" class="cp-avatar-rect" alt="${user.username || ''}">
        <div class="cp-info">
          <p class="cp-name">${nameAge}</p>
          ${distText ? `<p class="cp-distance">${distText}</p>` : ''}
        </div>
        <button class="cp-btn" data-action="expand">Ver Perfil</button>
      </div>
    `)
    .addTo(map);

  cinematicPopup.getElement().querySelector('[data-action="expand"]')
    .addEventListener('click', () => {
      closeCinematicPopup();
      showUserPopup(user);
    });
}

function closeCinematicPopup() {
  if (cinematicPopup) { cinematicPopup.remove(); cinematicPopup = null; }
  if (activeMarkerEl) { activeMarkerEl.style.opacity = '1'; activeMarkerEl = null; }
  resetCamera();
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
  const metersPerPixel = 156543.03392 * Math.abs(Math.cos(fixedUserLat * Math.PI / 180)) / Math.pow(2, zoom);
  const radiusInPixels = currentRangeMeters / metersPerPixel;
  container.style.setProperty('--radar-radius', `${radiusInPixels}px`);

  // 3. Círculo Geográfico (Turf.js no Mapbox)
  if (map.isStyleLoaded()) {
    const center = [fixedUserLng, fixedUserLat];
    const circle = turf.circle(center, currentRangeMeters / 1000, { steps: 64, units: 'kilometers' });

    if (map.getSource(radarSourceId)) {
      map.getSource(radarSourceId).setData(circle);
    } else {
      map.addSource(radarSourceId, { 'type': 'geojson', 'data': circle });
      map.addLayer({
        'id': radarLayerId,
        'type': 'fill',
        'source': radarSourceId,
        'paint': { 'fill-color': '#F4E4BC', 'fill-opacity': 0.1 }
      });
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

      const jitter = () => (Math.random() - 0.5) * 0.0005;
      uLat += jitter();
      uLng += jitter();

      if (!isNaN(uLat) && !isNaN(uLng)) {
        const el = document.createElement('div');
        el.className = 'premium-marker';
        el.innerHTML = `<img src="${user.avatar_url || '/default-avatar.png'}" class="premium-marker-img" alt="${user.username || ''}">`;

        const marker = new mapboxgl.Marker(el)
          .setLngLat([uLng, uLat])
          .addTo(map);
        mapboxUserMarkers[user.id] = marker;
        el.addEventListener('click', (e) => {
          e.stopPropagation();
          if (activeMarkerEl && activeMarkerEl !== el) activeMarkerEl.style.opacity = '1';
          activeMarkerEl = el;
          el.style.opacity = '0';
          isCinematicMode = true;
          document.body.classList.add('cinematic-mode');
          stopRotation();
          map.flyTo({ center: [uLng, uLat], zoom: 18, pitch: 60, duration: 2000, essential: true });
          openCinematicPopup(user, [uLng, uLat]);
          map.once('moveend', () => {
            setTimeout(() => {
              if (!isCinematicMode) return;
              startTimedRotation(null);
            }, 50);
          });
        });
      }

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
            const markerEl = mapboxUserMarkers[user.id]?.getElement()?.querySelector('.premium-marker');
            if (activeMarkerEl && activeMarkerEl !== markerEl) activeMarkerEl.style.opacity = '1';
            if (markerEl) { activeMarkerEl = markerEl; markerEl.style.opacity = '0'; }
            isCinematicMode = true;
            stopRotation();
            map.flyTo({ center: [uLng, uLat], zoom: 18, pitch: 60, duration: 2000, essential: true });
            openCinematicPopup(user, [uLng, uLat]);
            map.once('moveend', () => {
              setTimeout(() => {
                if (!isCinematicMode) return;
                startTimedRotation(null);
              }, 50);
            });
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

  mapElement.innerHTML = '';

  // Inicia em 2D (pitch 0, bearing 0)
  map = new mapboxgl.Map({
    container: 'map-3d',
    style: 'mapbox://styles/mapbox/standard',
    center: [-39.2781, -14.7876],
    zoom: 14,
    pitch: 0,
    bearing: 0,
    antialias: true,
    trackResize: true,
    fadeDuration: 0
  });

  // Fechar popup cinematográfico ao clicar no mapa
  map.on('click', () => { if (isCinematicMode || cinematicPopup) closeCinematicPopup(); });

  // Fade-in: usa 'load' (tiles prontos) em vez de 'style.load' para maior confiabilidade
  map.once('load', () => {
    const mapEl = document.getElementById('map-3d');
    if (mapEl) mapEl.classList.add('map-loaded');
  });

  map.on('style.load', () => {
    // Configurações do estilo "standard" — cores vivas, relevo e prédios 3D
    map.setConfigProperty('basemap', 'lightPreset', 'day');
    map.setConfigProperty('basemap', 'show3dObjects', true);
    map.setConfigProperty('basemap', 'show3dTrees', true);

    // Esconde labels de estabelecimentos (POIs) mantendo foco nos usuários
    map.setConfigProperty('basemap', 'showPointOfInterestLabels', false);

    if ("geolocation" in navigator) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          fixedUserLat = position.coords.latitude;
          fixedUserLng = position.coords.longitude;
          // Ao obter localização, voamos para o local mas mantemos 2D inicialmente se o zoom for baixo
          map.flyTo({ center: [fixedUserLng, fixedUserLat], zoom: 14, essential: true });
          updateRadarVisuals();
          loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
        },
        (error) => {
          console.warn("⚠️ Erro ao obter localização:", error.message);
          fixedUserLat = -14.2350;
          fixedUserLng = -51.9253;
          map.flyTo({ center: [fixedUserLng, fixedUserLat], zoom: 14, essential: true });
          updateRadarVisuals();
          loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
          if (error.code === 1) {
            alert("O GeoMatch precisa da sua localização para funcionar. Por favor, verifique as permissões do seu navegador/celular.");
          }
        },
        { enableHighAccuracy: true, maximumAge: 0, timeout: 10000 }
      );
    } else {
      fixedUserLat = -14.2350;
      fixedUserLng = -51.9253;
      map.flyTo({ center: [fixedUserLng, fixedUserLat], zoom: 14, essential: true });
      updateRadarVisuals();
      loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
    }
  });

  // Throttle via requestAnimationFrame para não recalcular turf.circle() a cada frame
  let rafPending = false;
  map.on('move', () => {
    if (rafPending) return;
    rafPending = true;
    requestAnimationFrame(() => {
      updateRadarVisuals();
      rafPending = false;
    });
  });
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
      if (fixedUserLat && fixedUserLng) {
        // Ao centralizar manualmente, forçamos o zoom para 3D
        map.flyTo({ center: [fixedUserLng, fixedUserLat], zoom: 16.5, pitch: 75, bearing: -20, essential: true });
      } else {
        map.flyTo({ center: [-39.2781, -14.7876], zoom: 16.5, pitch: 75, bearing: -20, essential: true });
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
           window.Android.iniciarRastreioSegundoPlano(userId);
        }
      } else {
        showTrackingToast("❌ Visibilidade em tempo real desativada. Sua localização não está mais visível.");
        if (window.Android) {
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
                setTimeout(() => { container.innerHTML = ""; }, 300);
              }
            };
            container.querySelectorAll(".close-modal-btn").forEach(btn => {
              btn.onclick = (e) => { e.preventDefault(); fecharModalGeoMatch(); };
            });
            if (backdrop) {
              backdrop.onclick = (e) => { if (e.target === backdrop) fecharModalGeoMatch(); };
            }
          }
          return;
        }

        if (!response.ok) throw new Error("Erro ao salvar no servidor");
        const data = await response.json();
        updateVisibilityUI(data.invisible);
      } catch (error) {
        console.error("Erro ao alternar visibilidade:", error);
      }
    });
  }

  // FECHAR POPUP APÓS AÇÃO
  document.addEventListener("turbo:submit-end", (e) => {
    const formId = e.target.id;
    if (formId === "popup-like-form" || formId === "popup-reject-form") {
      if (e.detail.success) { closeUserPopup(); }
    }
  });

  if (closePopupBtn) {
    const newBtn = closePopupBtn.cloneNode(true);
    closePopupBtn.parentNode.replaceChild(newBtn, closePopupBtn);
    newBtn.addEventListener("click", (e) => {
      e.preventDefault();
      closeUserPopup();
    });
  }

  if (popupOverlay) {
    popupOverlay.addEventListener("click", (e) => { closeUserPopup(); });
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
          if (isExpanded() && scrollTop > 0 && !popupHandle.contains(e.target)) { return; }
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
              if (deltaY > THRESHOLD) { popupContent.classList.add("expanded"); }
          } else {
              if (deltaY < -THRESHOLD) { popupContent.classList.remove("expanded"); }
          }
      };

      popupContent.addEventListener("touchstart", onTouchStart, { passive: false });
      popupContent.addEventListener("touchmove", onTouchMove, { passive: false });
      popupContent.addEventListener("touchend", onTouchEnd);
  }

  setInterval(() => {
    if (fixedUserLat && fixedUserLng && !isUserInvisible) {
      fetch(`/users/update_location?latitude=${fixedUserLat}&longitude=${fixedUserLng}`, {
        method: 'POST',
        headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content }
      });
    }
  }, 120000);

  setTimeout(() => {
    if (fabLiveTracking) {
      fabLiveTracking.click();
    }
  }, 1000);

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      if ("geolocation" in navigator) {
        navigator.geolocation.getCurrentPosition(
          (position) => {
            fixedUserLat = position.coords.latitude;
            fixedUserLng = position.coords.longitude;
            updateRadarVisuals();
            loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
          },
          (error) => { console.warn("⚠️ Localização erro:", error.message); },
          { enableHighAccuracy: true, maximumAge: 0, timeout: 10000 }
        );
      }
    }
  });

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
    .users-bottom-sheet { transition: height 0.4s cubic-bezier(0.25, 1, 0.5, 1); will-change: height; }
    .users-bottom-sheet.dragging { transition: none; }
    .premium-marker { width: 46px; height: 46px; border-radius: 50%; border: 3px solid #22c55e; box-shadow: 0 0 0 0 rgba(34,197,94,0.5), 0 4px 15px rgba(0,0,0,0.15); overflow: hidden; cursor: pointer; pointer-events: auto; position: relative; z-index: 10; transition: opacity 0.25s ease; will-change: transform; animation: markerPulse 2s ease-out infinite; }
    .premium-marker:hover { transform: scale(1.1); animation-play-state: paused; }
    .premium-marker-img { width: 100%; height: 100%; object-fit: cover; display: block; pointer-events: none; }
    @keyframes markerPulse { 0% { box-shadow: 0 0 0 0 rgba(34,197,94,0.6), 0 4px 15px rgba(0,0,0,0.15); } 70% { box-shadow: 0 0 0 12px rgba(34,197,94,0), 0 4px 15px rgba(0,0,0,0.15); } 100% { box-shadow: 0 0 0 0 rgba(34,197,94,0), 0 4px 15px rgba(0,0,0,0.15); } }
    .mapboxgl-marker { pointer-events: auto !important; }
    .cinematic-popup { will-change: transform; }
    .cinematic-popup .mapboxgl-popup-tip { display: none !important; }
    .cinematic-popup .mapboxgl-popup-content { background: rgba(255,255,255,0.7); backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); border-radius: 20px; border: 1px solid rgba(255,255,255,0.55); padding: 0; overflow: hidden; box-shadow: 0 8px 32px rgba(0,0,0,0.22), inset 0 1px 0 rgba(255,255,255,0.8); min-width: 180px; max-width: 210px; will-change: transform, opacity; transform: translateZ(0); animation: cpAppear 200ms ease-out forwards; }
    @keyframes cpAppear { 0% { opacity:0; transform:translateZ(0) scale(0.85); } 100% { opacity:1; transform:translateZ(0) scale(1); } }
    .cp-mini-card { display: flex; flex-direction: column; align-items: stretch; gap: 0; }
    .cp-avatar-rect { width: 100%; height: 145px; object-fit: cover; display: block; border-radius: 0; }
    .cp-info { text-align: center; line-height: 1.4; padding: 10px 14px 6px; }
    .cp-name { font-weight: 700; font-size: 1rem; color: #1a1a1a; margin: 0; letter-spacing: -0.2px; }
    .cp-distance { font-size: 0.78rem; color: #555; margin: 3px 0 0; }
    .cp-btn { width: calc(100% - 24px); margin: 0 12px 12px; background: linear-gradient(135deg,#d4be91,#b8975a); color: #1a1a1a; border: none; border-radius: 10px; padding: 9px 0; font-weight: 700; font-size: 0.82rem; cursor: pointer; letter-spacing: 0.3px; box-shadow: 0 3px 10px rgba(180,140,70,0.35); transition: transform 0.15s ease; }
    .cp-btn:active { transform: scale(0.95); }
    body.cinematic-mode .premium-marker { box-shadow: none !important; animation-play-state: paused !important; border-color: rgba(34,197,94,0.4) !important; }
  `;
  document.head.appendChild(style);
});