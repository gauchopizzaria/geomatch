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

    let currentRangeMeters = INITIAL_RANGE_METERS;
    let currentGenderFilter = "all";
    
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

    // ELEMENTOS DOM
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
    // LÓGICA CORE
    // ========================================

    function updateRadarCircle() {
      if (!fixedUserLat || !fixedUserLng) return;
      const radius = currentRangeMeters; 

      if (radarCircle) {
        radarCircle.setRadius(radius);
        radarCircle.setLatLng([fixedUserLat, fixedUserLng]);
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

    function updateSpotlightPosition() {
      if (!containerElement || !fixedUserLat || !fixedUserLng) return;
      const point = map.latLngToContainerPoint([fixedUserLat, fixedUserLng]);
      containerElement.style.setProperty('--radar-x', `${point.x}px`);
      containerElement.style.setProperty('--radar-y', `${point.y}px`);
    }

    function addUserMarker(lat, lng) {
      if (userMarker) map.removeLayer(userMarker);
      const userIcon = L.divIcon({
        html: `<div class="user-location-marker"><div class="user-location-pulse"></div><div class="user-location-dot"></div></div>`,
        className: "user-marker",
        iconSize: [40, 40],
      });
      userMarker = L.marker([lat, lng], { icon: userIcon, zIndexOffset: 1000 }).addTo(map);
    }

    function initializeMap(lat, lng) {
      fixedUserLat = lat;
      fixedUserLng = lng;
      
      map.setView([lat, lng], defaultZoom);
      
      addUserMarker(lat, lng);
      updateRadarCircle();
      updateSliderVisuals(currentRangeMeters);
      updateSpotlightPosition();
      
      showLoadingAnimation();
      loadNearbyUsers(lat, lng, currentRangeMeters, currentGenderFilter);
    }

    map.on('move', updateSpotlightPosition);
    map.on('resize', updateSpotlightPosition);

    // ========================================
    // API & FILTRAGEM (CORRIGIDO)
    // ========================================
    async function loadNearbyUsers(latitude, longitude, rangeMeters, genderFilter) {
      try {
        let url = `/users/nearby?latitude=${latitude}&longitude=${longitude}&range=${rangeMeters}`;
        if (genderFilter !== "all") url += `&gender=${genderFilter}`;

        const response = await fetch(url);
        if (!response.ok) throw new Error("Falha na rede");
        const users = await response.json();

        // --- CORREÇÃO DE FILTRO ---
        let filteredUsers = users.filter((user) => {
          // 1. Filtro de Gênero
          const g = (user.gender || "").toLowerCase();
          const matchesGender = (genderFilter === "all") ||
            (genderFilter === "male" && (g === "male" || g === "m" || g === "homem")) ||
            (genderFilter === "female" && (g === "female" || g === "f" || g === "mulher"));
          
          // 2. Filtro de Distância (Tolerante)
          // Verifica 'distance' OU 'distance_km'
          let distKm = user.distance_km || user.distance; 
          let matchesDistance = true;
          
          if (distKm !== undefined && distKm !== null) {
             const distMeters = parseFloat(distKm) * 1000;
             // Adiciona 50m de tolerância para não esconder usuários na borda
             matchesDistance = distMeters <= (rangeMeters + 50);
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
                // CORREÇÃO: Pega a distância certa
                const distDisplay = (user.distance_km || user.distance || 0);

                const avatarHtml = `
                  <div class="avatar-frame-wrapper">
                    <img src="${user.avatar_url || '/default-avatar.png'}" class="avatar-user-img">
                    <img src="${frameUrl}" class="avatar-frame-overlay">
                  </div>
                `;
                
                // CORREÇÃO: Garante que Lat/Lng sejam números válidos
                const uLat = parseFloat(user.latitude);
                const uLng = parseFloat(user.longitude);

                if (!isNaN(uLat) && !isNaN(uLng)) {
                    const icon = L.divIcon({ html: avatarHtml, className: "custom-marker", iconSize: [56, 56], popupAnchor: [0, -20] });
                    const marker = L.marker([uLat, uLng], { icon });
                    marker.on("click", () => showUserPopup(user));
                    userMarkersGroup.addLayer(marker);
                }

                const li = document.createElement("li");
                li.className = "user-list-item";
                li.innerHTML = `
                    ${avatarHtml}
                    <div class="user-list-info">
                        <span class="user-list-name">${user.username || user.display_name || 'Usuário'}</span>
                        <span class="user-list-distance">${distDisplay} km</span>
                    </div>
                `;
                li.addEventListener("click", () => {
                    if (!isNaN(uLat) && !isNaN(uLng)) {
                        map.flyTo([uLat, uLng], 16);
                        showUserPopup(user);
                    }
                });
                usersList.appendChild(li);
            });
        }
    }

  function showUserPopup(user) {
      if (!userPopup) return;
      
      userPopup.dataset.userId = user.id;

      // 1. Atualiza Visual
      const img = userPopup.querySelector("#popup-avatar");
      if(img) img.src = user.avatar_url || "/default-avatar.png";
      
      const name = userPopup.querySelector("#popup-username");
      if(name) name.textContent = user.username || user.display_name || "Usuário";
      
      const loc = userPopup.querySelector("#popup-location");
      if(loc) loc.textContent = user.city || "";
      
      const distBadge = userPopup.querySelector("#popup-distance");
      const distVal = user.distance_km || user.distance;
      if(distBadge) distBadge.textContent = distVal ? `${distVal} km` : "";

      // 2. ATUALIZA OS FORMULÁRIOS (Action URL)
      const forms = [
          document.getElementById("popup-reject-form"),
          document.getElementById("popup-chat-form"),
          document.getElementById("popup-like-form")
      ];

      forms.forEach(form => {
          if (form) {
              // Pega a URL original salva no data-base-action (ex: /start_chat/0)
              let baseUrl = form.getAttribute("data-base-action");
              
              // Se por acaso não tiver salvo, tenta pegar do action atual
              if (!baseUrl) {
                 baseUrl = form.action;
                 form.setAttribute("data-base-action", baseUrl);
              }

              // Substitui o ID '0' final pelo ID real do usuário
              // Regex: procura por /0 no final da string, opcionalmente seguido de slash
              const newUrl = baseUrl.replace(/\/0\/?(\?.*)?$/, '/' + user.id + '$1');
              
              // Se for o formulário de Like e usar query params (?user_id=0), usa outra lógica:
              if (newUrl.includes("user_id=")) {
                  form.action = newUrl.replace("user_id=0", `user_id=${user.id}`);
              } else {
                  form.action = newUrl;
              }
          }
      });

      // 3. Mostra o Popup
      userPopup.classList.remove("hidden");
      userPopup.classList.add("show");
    }

   // ========================================
   // CORREÇÃO: MODO INVISÍVEL
   // ========================================
    if (toggleVisibilityBtn) {
        const eyeOpen = toggleVisibilityBtn.querySelector(".eye-open");
        const eyeClosed = toggleVisibilityBtn.querySelector(".eye-closed");

        const updateVisibilityUI = (isInvisible) => {
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

        // CORREÇÃO: Agora o elemento existe no HTML, não vai dar erro
        const userData = document.getElementById('current-user-data'); 
        const initialInvisible = userData ? (userData.dataset.invisible === 'true') : false;
        
        updateVisibilityUI(initialInvisible);

        toggleVisibilityBtn.addEventListener("click", async () => {
            try {
                // Feedback visual imediato (Otimista)
                const isCurrentlyInvisible = toggleVisibilityBtn.classList.contains("active");
                // updateVisibilityUI(!isCurrentlyInvisible); // <-- REMOVIDO PARA NÃO ENGANAR O USUÁRIO FREE

                const token = document.querySelector('meta[name="csrf-token"]').content;
                const response = await fetch('/users/toggle_visibility', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token }
                });

                // SE O SERVIDOR DISSER QUE PRECISA DE UPGRADE (Status 403)
                if (response.status === 403) {
                    const data = await response.json();
                    if (data.upgrade_required) {
                        console.log("Upgrade necessário para modo invisível");
                        
                        // Busca o HTML do modal via fetch na rota que criamos antes
                        // Passamos type='invisible' para personalizar o texto
                        const modalResponse = await fetch('/plans/modal?type=invisible');
                        const modalHtml = await modalResponse.text();
                        
                        // Injeta o modal na tela
                        document.getElementById("upgrade-modal-container").innerHTML = modalHtml;
                    }
                    return; // Para por aqui
                }

                if (!response.ok) throw new Error("Erro ao salvar no servidor");
                
                const data = await response.json();
                updateVisibilityUI(data.invisible);
                
                if (data.invisible) {
                   // Lógica extra se ficou invisível (ex: parar GPS)
                }

            } catch (error) {
                console.error("Erro ao alternar visibilidade:", error);
            }
        });
    }
    
    // INICIALIZAÇÃO GEOLOCALIZAÇÃO
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

  // ========================================
    // 9. FECHAR POPUP APÓS AÇÃO (Like/Reject)
    // ========================================
    document.addEventListener("turbo:submit-end", (e) => {
        // Verifica se o envio veio de um dos formulários do popup
        const formId = e.target.id;
        
        if (formId === "popup-like-form" || formId === "popup-reject-form") {
            if (e.detail.success) {
                console.log("Ação realizada com sucesso! Fechando popup...");
                
                // Fecha o popup
                const popup = document.getElementById("user-popup");
                if (popup) {
                    popup.classList.add("hidden");
                    popup.classList.remove("show");
                }
                
                // Opcional: Remover o marcador do mapa para dar feedback visual
                // Isso exigiria buscar o marcador pelo ID, mas só fechar o popup já resolve.
            }
        }

        // ========================================
    // FUNÇÃO GLOBAL DE FECHAR (NOVA)
    // ========================================
    function closeUserPopup() {
        const popup = document.getElementById("user-popup");
        if (popup) {
            popup.classList.add("hidden");
            popup.classList.remove("show");
            
            // Opcional: Limpar os IDs dos formulários para evitar conflitos futuros
            const rejectInput = document.getElementById("popup-reject-input");
            const likeInput = document.getElementById("popup-like-input");
            if(rejectInput) rejectInput.value = "";
            if(likeInput) likeInput.value = "";
        }
    }

    // 1. Evento no Botão X
    if (closePopupBtn) {
        // Remove listeners antigos para evitar duplicação (boa prática)
        const newBtn = closePopupBtn.cloneNode(true);
        closePopupBtn.parentNode.replaceChild(newBtn, closePopupBtn);
        
        newBtn.addEventListener("click", (e) => {
            e.preventDefault();
            console.log("Botão fechar clicado");
            closeUserPopup();
        });
    }

    // 2. Evento no Fundo Escuro (Overlay)
    if (popupOverlay) {
        popupOverlay.addEventListener("click", (e) => {
            console.log("Fundo clicado");
            closeUserPopup();
        });
    }

    // 3. Fechar Automaticamente após Like ou Reject (Turbo)
    document.addEventListener("turbo:submit-end", (e) => {
        const formId = e.target.id;
        
        // Se o envio veio do popup (Like ou Reject) e deu certo (código 200)
        if ((formId === "popup-like-form" || formId === "popup-reject-form") && e.detail.success) {
            console.log("Ação concluída com sucesso via Turbo. Fechando...");
            closeUserPopup();
        }
    });


    // Fechar ao clicar no fundo escuro (Overlay)
    const popupOverlay = document.querySelector(".popup-overlay");
    if (popupOverlay) {
        popupOverlay.addEventListener("click", (e) => {
            // Previne que o clique passe para o mapa
            e.stopPropagation(); 
            const popup = document.getElementById("user-popup");
            popup.classList.add("hidden");
            popup.classList.remove("show");
        });
    }


    });

});