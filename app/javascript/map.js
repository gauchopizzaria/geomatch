import L from "leaflet";
window.L = L;

const INITIAL_RANGE_METERS = 150; 
const STORAGE_KEYS = {
  RANGE: "geomatch_range",
  GENDER_FILTER: "geomatch_gender_filter",
  INVISIBLE_MODE: "geomatch_invisible_mode",
};

["DOMContentLoaded", "turbo:load"].forEach((evt) => {
  document.addEventListener(evt, () => {
    const mapContainer = document.getElementById("map");
    if (!mapContainer) return;

    const assetsData = document.getElementById('assets-data');
    const frameUrl = assetsData ? assetsData.dataset.frameUrl : ''; 

    // ========================================
    // 1. CONFIGURAÇÃO DO MAPA
    // ========================================
    const defaultLat = -14.788;
    const defaultLng = -39.278;
    const defaultZoom = 15;

    const map = L.map("map", {
      zoomControl: false,
      attributionControl: false
    }).setView([defaultLat, defaultLng], defaultZoom);

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
    }).addTo(map);

    // --- VARIÁVEIS DE ESTADO ---
    let currentRangeMeters = INITIAL_RANGE_METERS;
    let currentGenderFilter = "all";
    
    // ONDE O USUÁRIO ESTÁ (A LUZ FICA AQUI)
    let fixedUserLat = null;
    let fixedUserLng = null;

    let radarCircle = null;
    let userMarker = null;

    const savedRange = localStorage.getItem(STORAGE_KEYS.RANGE);
    const savedGender = localStorage.getItem(STORAGE_KEYS.GENDER_FILTER);

    if (savedRange) currentRangeMeters = parseInt(savedRange, 10);
    if (savedGender) currentGenderFilter = savedGender;

    const userMarkersGroup = L.featureGroup();
    map.addLayer(userMarkersGroup);

    // ========================================
    // 2. ELEMENTOS DO DOM
    // ========================================
    const rangeSlider = document.getElementById("radar-range");
    const rangeValueText = document.getElementById("range-value-text");
    const radarControl = document.querySelector('.radar-control-floating');
    const containerElement = document.querySelector('.discover-fullscreen-container');
    const usersList = document.getElementById("users-list");
    const usersCountElement = document.getElementById("nearby-count");
    const userPopup = document.getElementById("user-popup");
    const closePopupBtn = document.getElementById("close-popup-btn");
    const popupOverlay = document.querySelector(".popup-overlay");
    const fabCenterMap = document.getElementById("fab-center-map");
    const toggleVisibilityBtn = document.getElementById("toggle-visibility-btn");
    const genderToggleBtn = document.getElementById("gender-filter-toggle");

    // Stories Elements (Mantido igual)
    const storiesSection = document.getElementById("stories-section");
    const storiesToggleBtn = document.getElementById("stories-toggle-btn");
    const addStoryBtn = document.getElementById("add-story-btn");
    const addStoryModal = document.getElementById("add-story-modal");
    const modalOverlay = document.getElementById("modal-overlay");
    const closeModalBtn = document.getElementById("close-modal-btn");
    const cancelStoryBtn = document.getElementById("cancel-story-btn");

    // ========================================
    // 3. SLIDER DE RAIO
    // ========================================
    let updateSliderVisuals = () => {}; 
    if (rangeSlider && rangeValueText) {
      updateSliderVisuals = (val) => {
        rangeValueText.textContent = `${val}m`;
        const max = rangeSlider.max || 300;
        const percent = (val / max) * 100;
        rangeSlider.style.backgroundImage = `linear-gradient(to right, #f4e4bc 0%, #f4e4bc ${percent}%, transparent ${percent}%, transparent 100%)`;
        
        if (containerElement) {
           containerElement.style.setProperty('--radar-radius', `${val}px`);
        }
      };
      rangeSlider.value = currentRangeMeters;
      updateSliderVisuals(currentRangeMeters);

      rangeSlider.addEventListener("input", (e) => {
        const val = parseInt(e.target.value, 10);
        currentRangeMeters = val;
        updateSliderVisuals(val); 
        updateRadarCircle();      
      });
      
      rangeSlider.addEventListener("change", () => {
        localStorage.setItem(STORAGE_KEYS.RANGE, currentRangeMeters);
        // Recarrega usuários na posição do USUÁRIO (não do centro da tela)
        if (fixedUserLat && fixedUserLng) {
          loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
        }
      });
    }

    // ========================================
    // 4. RADAR DRAGGABLE
    // ========================================
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

    // ========================================
    // 5. FILTRO GÊNERO
    // ========================================
    if (genderToggleBtn) {
      genderToggleBtn.addEventListener("click", () => {
        if (currentGenderFilter === "all") currentGenderFilter = "male";
        else if (currentGenderFilter === "male") currentGenderFilter = "female";
        else currentGenderFilter = "all";

        localStorage.setItem(STORAGE_KEYS.GENDER_FILTER, currentGenderFilter);
        genderToggleBtn.style.opacity = "0.5";
        setTimeout(() => genderToggleBtn.style.opacity = "1", 200);

        if (fixedUserLat && fixedUserLng) {
          showLoadingAnimation();
          loadNearbyUsers(fixedUserLat, fixedUserLng, currentRangeMeters, currentGenderFilter);
        }
      });
    }

    // ========================================
    // 6. BOTTOM SHEET
    // ========================================
    const bottomSheet = document.querySelector(".users-bottom-sheet");
    const handle = document.querySelector(".bottom-sheet-handle");
    if (bottomSheet && handle) {
      let startY = 0; let startHeight = 0; let isDraggingSheet = false;
      const SNAP_MIN = 25; const SNAP_MAX = 85; const SNAP_THRESHOLD = 50; 
      const onDragStart = (e) => {
        isDraggingSheet = true;
        bottomSheet.classList.add("dragging"); 
        startY = e.touches ? e.touches[0].clientY : e.clientY;
        startHeight = bottomSheet.getBoundingClientRect().height;
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
        if (currentVh > SNAP_THRESHOLD) bottomSheet.style.height = `${SNAP_MAX}vh`;
        else bottomSheet.style.height = `${SNAP_MIN}vh`;
      };
      handle.addEventListener("mousedown", onDragStart);
      handle.addEventListener("touchstart", onDragStart, { passive: false });
      window.addEventListener("mousemove", onDragMove);
      window.addEventListener("touchmove", onDragMove, { passive: false });
      window.addEventListener("mouseup", onDragEnd);
      window.addEventListener("touchend", onDragEnd);
    }

    // ========================================
    // 7. STORIES
    // ========================================
    if (storiesToggleBtn && storiesSection) {
        storiesToggleBtn.addEventListener("click", (e) => { e.stopPropagation(); storiesSection.classList.toggle("expanded"); });
        document.addEventListener("click", (e) => { if (!storiesSection.contains(e.target)) storiesSection.classList.remove("expanded"); });
    }
    if (addStoryBtn) {
        addStoryBtn.addEventListener("click", (e) => {
            e.stopPropagation();
            if(addStoryModal) { addStoryModal.classList.remove("hidden"); if(modalOverlay) modalOverlay.classList.remove("hidden"); }
        });
    }
    const hideAddStoryModal = () => { if(addStoryModal) addStoryModal.classList.add("hidden"); if(modalOverlay) modalOverlay.classList.add("hidden"); };
    if (closeModalBtn) closeModalBtn.addEventListener("click", hideAddStoryModal);
    if (cancelStoryBtn) cancelStoryBtn.addEventListener("click", hideAddStoryModal);
    if (modalOverlay) modalOverlay.addEventListener("click", hideAddStoryModal);

    // ========================================
    // 8. HELPERS
    // ========================================
    function showLoadingAnimation() {
      if (usersList) {
        usersList.innerHTML = `
          <li class="loading-skeleton"><div class="skeleton-avatar"></div><div class="skeleton-text"><div class="skeleton-line"></div></div></li>
          <li class="loading-skeleton"><div class="skeleton-avatar"></div><div class="skeleton-text"><div class="skeleton-line"></div></div></li>
        `;
      }
      if (usersCountElement) usersCountElement.textContent = "...";
    }
    function hideLoadingAnimation() { }

    // ========================================
    // LÓGICA CORE: POSIÇÃO DA LUZ E RADAR
    // ========================================

    // Atualiza o Círculo (Leaflet) -> FIXO NA POSIÇÃO GEOGRÁFICA DO USUÁRIO
    function updateRadarCircle() {
      if (!fixedUserLat || !fixedUserLng) return;
      const radius = currentRangeMeters; 

      if (radarCircle) {
        radarCircle.setRadius(radius);
        radarCircle.setLatLng([fixedUserLat, fixedUserLng]); // Sempre no GPS
      } else {
        radarCircle = L.circle([fixedUserLat, fixedUserLng], {
          radius: radius,
          color: '#d4af37',
          fillColor: '#d4af37',
          fillOpacity: 0.1,
          weight: 1,
          interactive: false,
        }).addTo(map);
      }
    }

    // Atualiza o Spotlight (CSS) -> CALCULA ONDE O USUÁRIO ESTÁ NA TELA
    function updateSpotlightPosition() {
      if (!containerElement || !fixedUserLat || !fixedUserLng) return;

      // MÁGICA: Converte Lat/Lng do Usuário para Pixels na tela (X, Y)
      // Se você arrastar o mapa, esse ponto X/Y vai mudar, movendo a luz
      const point = map.latLngToContainerPoint([fixedUserLat, fixedUserLng]);
      
      containerElement.style.setProperty('--radar-x', `${point.x}px`);
      containerElement.style.setProperty('--radar-y', `${point.y}px`);
    }

    // Marcador do Usuário -> FIXO
    function addUserMarker(lat, lng) {
      if (userMarker) map.removeLayer(userMarker);
      const userIcon = L.divIcon({
        html: `<div class="user-location-marker"><div class="user-location-pulse"></div><div class="user-location-dot"></div></div>`,
        className: "user-marker",
        iconSize: [40, 40],
      });
      userMarker = L.marker([lat, lng], { icon: userIcon, zIndexOffset: 1000 }).addTo(map);
    }

    // Inicialização
    function initializeMap(lat, lng) {
      fixedUserLat = lat;
      fixedUserLng = lng;
      
      map.setView([lat, lng], defaultZoom);
      
      addUserMarker(lat, lng);
      updateRadarCircle(); // Cria o círculo no usuário
      updateSliderVisuals(currentRangeMeters);
      updateSpotlightPosition(); // Alinha a luz com o usuário
      
      showLoadingAnimation();
      loadNearbyUsers(lat, lng, currentRangeMeters, currentGenderFilter);
    }

    // --- EVENTO CRÍTICO: MOVER O MAPA ---
    map.on('move', () => {
        // Quando arrasta o mapa:
        // 1. O Mapa move (nativo do Leaflet)
        // 2. O Marcador e o Círculo Amarelo movem junto com o mapa (comportamento padrão de camadas)
        
        // 3. Precisamos apenas atualizar a MÁSCARA (Spotlight) para seguir o pino visualmente
        updateSpotlightPosition();
        
        // Nota: Se arrastar muito longe, o 'point.x' vai ser negativo ou muito grande
        // e a luz vai sair da tela, deixando tudo escuro. É o esperado.
    });

    map.on('resize', updateSpotlightPosition);

    // ========================================
    // API
    // ========================================
    async function loadNearbyUsers(latitude, longitude, rangeMeters, genderFilter) {
      try {
        // Busca baseada na posição do USUÁRIO, não do centro da tela
        let url = `/users/nearby?latitude=${latitude}&longitude=${longitude}&range=${rangeMeters}`;
        if (genderFilter !== "all") url += `&gender=${genderFilter}`;

        const response = await fetch(url);
        if (!response.ok) throw new Error("Falha na rede");
        const users = await response.json();

        let filteredUsers = users.filter((user) => {
          const g = (user.gender || "").toLowerCase();
          const matchesGender = (genderFilter === "all") ||
            (genderFilter === "male" && (g === "male" || g === "m" || g === "homem")) ||
            (genderFilter === "female" && (g === "female" || g === "f" || g === "mulher"));
          
          let matchesDistance = true;
          if (user.distance_km !== undefined && user.distance_km !== null) {
             const distMeters = parseFloat(user.distance_km) * 1000;
             matchesDistance = distMeters <= (rangeMeters + 10);
          }
          return matchesGender && matchesDistance;
        });

        updateUIWithUsers(filteredUsers);
        hideLoadingAnimation();
      } catch (error) {
        console.error("Erro ao carregar:", error);
        hideLoadingAnimation();
        if (usersList) usersList.innerHTML = '<li class="text-center loading-text">Ninguém encontrado</li>';
      }
    }

    function updateUIWithUsers(users) {
        if (usersCountElement) usersCountElement.textContent = users.length;
        userMarkersGroup.clearLayers();
        if (usersList) {
            usersList.innerHTML = "";
            if (users.length === 0) {
                usersList.innerHTML = '<li class="text-center loading-text">Ninguém por perto...</li>';
                return;
            }
            users.forEach(user => {
                const avatarHtml = `
                  <div class="avatar-frame-wrapper">
                    <img src="${user.avatar_url || '/default-avatar.png'}" class="avatar-user-img">
                    <img src="${frameUrl}" class="avatar-frame-overlay">
                  </div>
                `;
                if (user.latitude && user.longitude) {
                    const icon = L.divIcon({ html: avatarHtml, className: "custom-marker", iconSize: [56, 56], popupAnchor: [0, -20] });
                    const marker = L.marker([user.latitude, user.longitude], { icon });
                    marker.on("click", () => showUserPopup(user));
                    userMarkersGroup.addLayer(marker);
                }
                const li = document.createElement("li");
                li.className = "user-list-item";
                li.innerHTML = `
                    ${avatarHtml}
                    <div class="user-list-info">
                        <span class="user-list-name">${user.username || 'Usuário'}</span>
                        <span class="user-list-distance">${user.distance_km ? user.distance_km + ' km' : 'Perto'}</span>
                    </div>
                `;
                li.addEventListener("click", () => {
                    map.flyTo([user.latitude, user.longitude], 16);
                    showUserPopup(user);
                });
                usersList.appendChild(li);
            });
        }
    }

    function showUserPopup(user) {
      if (!userPopup) return;
      userPopup.dataset.userId = user.id;
      const img = userPopup.querySelector("#popup-avatar");
      if(img) img.src = user.avatar_url || "/default-avatar.png";
      const name = userPopup.querySelector("#popup-username");
      if(name) name.textContent = user.username || "Usuário";
      const loc = userPopup.querySelector("#popup-location");
      if(loc) loc.textContent = user.city || "";
      const distBadge = userPopup.querySelector("#popup-distance");
      if(distBadge) distBadge.textContent = user.distance_km ? `${user.distance_km} km` : "";
      userPopup.classList.remove("hidden");
      userPopup.classList.add("show");
    }

    if (closePopupBtn) closePopupBtn.addEventListener("click", () => { userPopup.classList.add("hidden"); userPopup.classList.remove("show"); });
    if (popupOverlay) popupOverlay.addEventListener("click", () => { userPopup.classList.add("hidden"); userPopup.classList.remove("show"); });

    // Botão Centralizar (Volta para o usuário)
    if (fabCenterMap) {
        fabCenterMap.addEventListener("click", () => {
            if (fixedUserLat && fixedUserLng) { 
                map.flyTo([fixedUserLat, fixedUserLng], 15); 
            }
        });
    }

   // ========================================
    // CORREÇÃO: MODO INVISÍVEL
    // ========================================
    if (toggleVisibilityBtn) {
        const eyeOpen = toggleVisibilityBtn.querySelector(".eye-open");
        const eyeClosed = toggleVisibilityBtn.querySelector(".eye-closed");

        // Função visual para alternar ícones
        const updateVisibilityUI = (isInvisible) => {
            if (isInvisible) {
                toggleVisibilityBtn.classList.add("active"); // Estilo de ativado (vermelho/dourado)
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

        // 1. ESTADO INICIAL:
        // Idealmente, o Rails deve passar esse estado no HTML (data-attribute)
        // Se você tiver <div id="current-user-data" data-invisible="<%= current_user.invisible %>"></div>
        const userData = document.getElementById('current-user-data'); // Crie esse elemento no layout se não tiver
        const initialInvisible = userData ? (userData.dataset.invisible === 'true') : false;
        
        // Aplica o estado inicial visualmente
        updateVisibilityUI(initialInvisible);

        // 2. EVENTO DE CLICK
        toggleVisibilityBtn.addEventListener("click", async () => {
            try {
                // Feedback visual imediato (Otimista)
                const isCurrentlyInvisible = toggleVisibilityBtn.classList.contains("active");
                updateVisibilityUI(!isCurrentlyInvisible);

                // Chama o servidor
                const token = document.querySelector('meta[name="csrf-token"]').content;
                const response = await fetch('/users/toggle_visibility', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': token
                    }
                });

                if (!response.ok) {
                    throw new Error("Erro ao salvar no servidor");
                }

                const data = await response.json();
                
                // Confirma o estado real vindo do servidor
                updateVisibilityUI(data.invisible);

                // Opcional: Se ficou invisível, parar de enviar localização ou limpar mapa
                if (data.invisible) {
                    console.log("Você está invisível agora.");
                    // Aqui você pode adicionar lógica para parar o watchPosition se usar
                }

            } catch (error) {
                console.error("Erro ao alternar visibilidade:", error);
                // Reverte visualmente se deu erro
                alert("Não foi possível alterar a visibilidade. Verifique sua conexão.");
                const isCurrentlyInvisible = toggleVisibilityBtn.classList.contains("active");
                updateVisibilityUI(!isCurrentlyInvisible); 
            }
        });
    }
    
    if ("geolocation" in navigator) {
        navigator.geolocation.getCurrentPosition(
            (position) => initializeMap(position.coords.latitude, position.coords.longitude),
            () => initializeMap(defaultLat, defaultLng),
            { enableHighAccuracy: true }
        );
    } else {
        initializeMap(defaultLat, defaultLng);
    }

    const style = document.createElement("style");
    style.textContent = `
    .user-location-marker { position: relative; width: 40px; height: 40px; }
    .user-location-dot { width: 12px; height: 12px; background: #d4af37; border-radius: 50%; border: 2px solid #fff; position: relative; z-index: 10; top: 14px; left: 14px; }
    .user-location-pulse { position: absolute; width: 40px; height: 40px; border-radius: 50%; border: 2px solid rgba(212, 175, 55, 0.5); animation: pulse 2s infinite; }
    @keyframes pulse { 0% { transform: scale(0.5); opacity: 1; } 100% { transform: scale(1.5); opacity: 0; } }
    .loading-skeleton { display: flex; gap: 10px; padding: 10px; background: #252527; border-radius: 8px; margin-bottom: 5px; }
    .skeleton-avatar { width: 40px; height: 40px; background: #444; border-radius: 50%; }
    .skeleton-text { flex: 1; display: flex; flex-direction: column; gap: 5px; justify-content: center; }
    .skeleton-line { height: 10px; background: #444; border-radius: 4px; width: 80%; }
    `;
    document.head.appendChild(style);
  });
});