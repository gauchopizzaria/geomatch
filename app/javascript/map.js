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

    // Recalcula o tamanho do círculo visual quando o zoom muda
    map.on('zoom', () => {
        updateCSSRadarRadius();
    });

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
    // 3. SLIDER DE RAIO & SINCRONIZAÇÃO VISUAL
    // ========================================
    
    // Função para converter Metros em Pixels baseado no Zoom
    function updateCSSRadarRadius() {
        if (!map || !fixedUserLat || !containerElement) return;

        // 1. Obtém a escala atual do mapa (metros por pixel)
        const zoom = map.getZoom();
        const metersPerPixel = 156543.03392 * Math.abs(Math.cos(fixedUserLat * Math.PI / 180)) / Math.pow(2, zoom);

        // 2. Converte o raio selecionado (metros) para pixels
        const radiusInPixels = currentRangeMeters / metersPerPixel;

        // 3. Atualiza a variável CSS com o valor calculado
        containerElement.style.setProperty('--radar-radius', `${radiusInPixels}px`);
    }

    let updateSliderVisuals = () => {}; 
    if (rangeSlider && rangeValueText) {
      updateSliderVisuals = (val) => {
        // Atualiza Texto
        rangeValueText.textContent = `${val}m`;
        
        // Atualiza Cor do Slider
        const max = rangeSlider.max || 300;
        const percent = (val / max) * 100;
        rangeSlider.style.backgroundImage = `linear-gradient(to right, #f4e4bc 0%, #f4e4bc ${percent}%, transparent ${percent}%, transparent 100%)`;
        
        // A atualização do raio visual agora acontece via updateCSSRadarRadius()
        updateCSSRadarRadius();
      };

      // Inicializa visual do slider
      rangeSlider.value = currentRangeMeters;
      
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
    // API & FILTRAGEM
    // ========================================
    async function loadNearbyUsers(latitude, longitude, rangeMeters, genderFilter) {
      try {
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
          
          let distKm = user.distance_km || user.distance; 
          let matchesDistance = true;
          
          if (distKm !== undefined && distKm !== null) {
              const distMeters = parseFloat(distKm) * 1000;
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
                const distDisplay = (user.distance_km || user.distance || 0);

                const avatarHtml = `
                  <div class="avatar-frame-wrapper">
                    <img src="${user.avatar_url || '/default-avatar.png'}" class="avatar-user-img">
                    <img src="${frameUrl}" class="avatar-frame-overlay">
                  </div>
                `;
                
                let uLat = parseFloat(user.latitude);
                let uLng = parseFloat(user.longitude);

                // Verifica se há outros usuários na mesma posição exata
             // e adiciona um desvio de ~1-2 metros (0.00001 graus)
                const jitter = () => (Math.random() - 0.5) * 0.0001;
                uLat += jitter();
                uLng += jitter();


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

      // 1. Atualiza Visual Básico
      const img = userPopup.querySelector("#popup-avatar");
      if(img) img.src = user.avatar_url || "/default-avatar.png";
      
      const name = userPopup.querySelector("#popup-username");
      if(name) name.textContent = user.username || user.display_name || "Usuário";
      
      const loc = userPopup.querySelector("#popup-location");
      if(loc) loc.textContent = user.city || "Localização desconhecida";
      
      const distBadge = userPopup.querySelector("#popup-distance");
      const distVal = user.distance_km || user.distance;
      if(distBadge) distBadge.textContent = distVal ? `${distVal} km` : "";

      // --- 2. NOVOS DADOS (DETALHES) ---
      
      // Bio
      const bio = userPopup.querySelector("#popup-bio");
      if(bio) bio.textContent = user.bio || "📚 Advogado de 32 anos, apaixonado por livros, palavras e boas histórias. ✍️ Explorador do mundo, sempre em busca de destinos fascinantes, culturas diferentes e pratos que contam histórias através do sabor. 🌍🍴 Se viagens, literatura e descobertas gastronômicas também fazem seu coração bater mais forte, vamos compartilhar essa jornada! 😉";

      // Gênero
      const gender = userPopup.querySelector("#popup-gender");
      if(gender) gender.textContent = user.gender ? (user.gender === 'male' ? 'Masculino' : 'Feminino') : "Não informado";
      
      // Interesse
      const interest = userPopup.querySelector("#popup-interest");
      if(interest) interest.textContent = user.interested_in ? `Busca: ${user.interested_in}` : "Busca: Todos";

      // Tags (Interesses)
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

      // --- RESETAR ESTADO DO POPUP (SEMPRE ABRIR PEQUENO) ---
      const content = userPopup.querySelector(".popup-content-fullscreen");
      if(content) content.classList.remove("expanded");


      // ... (LÓGICA DOS FORMULÁRIOS) ...
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

      // 3. Mostra o Popup
      userPopup.classList.remove("hidden");
      userPopup.classList.add("show");
    }

    // ========================================
    // CORREÇÃO 1: BOTÃO CENTRALIZAR MAPA (ESTAVA FALTANDO)
    // ========================================
    if (fabCenterMap) {
        fabCenterMap.addEventListener("click", () => {
            console.log("Centralizar mapa clicado");
            if (fixedUserLat && fixedUserLng) {
                map.flyTo([fixedUserLat, fixedUserLng], defaultZoom, {
                    animate: true,
                    duration: 1.5
                });
            } else {
                // Fallback se ainda não pegou o GPS
                map.flyTo([defaultLat, defaultLng], defaultZoom);
            }
        });
    }

    // ========================================
    // CORREÇÃO 2: MODO INVISÍVEL
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

        const userData = document.getElementById('current-user-data'); 
        const initialInvisible = userData ? (userData.dataset.invisible === 'true') : false;
        
        updateVisibilityUI(initialInvisible);

        toggleVisibilityBtn.addEventListener("click", async () => {
            console.log("Botão Invisibilidade clicado");
            try {
                const token = document.querySelector('meta[name="csrf-token"]').content;
                const response = await fetch('/users/toggle_visibility', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token }
                });

                // SE O SERVIDOR DISSER QUE PRECISA DE UPGRADE (Status 403)
                if (response.status === 403) {
                    console.log("Status 403: Upgrade necessário");
                    const data = await response.json();
                    if (data.upgrade_required) {
                        const modalResponse = await fetch('/plans/modal?type=invisible');
                        const modalHtml = await modalResponse.text();
                        const container = document.getElementById("upgrade-modal-container");
                        container.innerHTML = modalHtml;
                        
                        // Lógica extra para fechar o modal carregado via AJAX, se necessário
                        const newModalCloseBtn = container.querySelector(".close-modal-btn"); 
                        if(newModalCloseBtn) {
                            newModalCloseBtn.addEventListener("click", () => {
                                container.innerHTML = "";
                            });
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
    
    // ========================================
    // INICIALIZAÇÃO GEOLOCALIZAÇÃO (TEMPO REAL & RETOMADA)
    // ========================================
    
    // Função reutilizável para forçar o GPS
    const forceLocationUpdate = () => {
        if ("geolocation" in navigator) {
            console.log("📍 Solicitando posição atualizada (Sem Cache)...");
            
            navigator.geolocation.getCurrentPosition(
                (position) => {
                    console.log("✅ Nova localização obtida:", position.coords.latitude, position.coords.longitude);
                    // Atualiza tudo (Mapa, Marcador, Usuários Próximos)
                    initializeMap(position.coords.latitude, position.coords.longitude);
                },
                (error) => {
                    console.warn("⚠️ Erro ao obter localização:", error.message);
                    
                    // Se falhar e a gente ainda não tiver nenhuma localização, usa o padrão
                    if (!fixedUserLat || !fixedUserLng) {
                        initializeMap(defaultLat, defaultLng);
                    }
                    
                    // Alerta apenas se for erro de permissão (para não spammar o usuário se for só sinal fraco)
                    if (error.code === 1) {
                        alert("O GeoMatch precisa da sua localização para funcionar. Por favor, verifique as permissões do seu navegador/celular.");
                    }
                },
                {
                    enableHighAccuracy: true, // Força uso do GPS
                    maximumAge: 0,            // OBRIGATÓRIO: Não aceita posição cacheada, quer a nova
                    timeout: 10000            // Espera 10s antes de dar erro
                }
            );
        } else {
            initializeMap(defaultLat, defaultLng);
        }
    };

    // 1. Chama imediatamente ao abrir
    forceLocationUpdate();

    // 2. Chama toda vez que o usuário voltar para a aba/app (Sair e Entrar)
    document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible") {
            console.log("👁️ Usuário voltou para o app. Atualizando GPS...");
            forceLocationUpdate();
        }
    });

    const style = document.createElement("style");
    // ... (o resto do seu estilo permanece igual)
    style.textContent = `
    .user-location-marker { position: relative; width: 40px; height: 40px; }
    .user-location-dot { width: 12px; height: 12px; background: #ccc099; border-radius: 50%; border: 2px solid #fff; position: relative; z-index: 10; top: 14px; left: 14px; }
    .user-location-pulse { position: absolute; width: 40px; height: 40px; border-radius: 50%; border: 2px solid rgba(212, 175, 55, 0.5); animation: pulse 2s infinite; }
    @keyframes pulse { 0% { transform: scale(0.5); opacity: 1; } 100% { transform: scale(1.5); opacity: 0; } }
    .loading-skeleton { display: flex; gap: 10px; padding: 10px; background: #252527; border-radius: 8px; margin-bottom: 5px; }
    .skeleton-avatar { width: 40px; height: 40px; background: #444; border-radius: 50%; }
    .skeleton-text { flex: 1; display: flex; flex-direction: column; gap: 5px; justify-content: center; }
    .skeleton-line { height: 10px; background: #444; border-radius: 4px; width: 80%; }
    `;
    document.head.appendChild(style);

    // ========================================
    // 9. FECHAR POPUP APÓS AÇÃO (Like/Reject)
    // ========================================
    document.addEventListener("turbo:submit-end", (e) => {
        const formId = e.target.id;
        if (formId === "popup-like-form" || formId === "popup-reject-form") {
            if (e.detail.success) {
                closeUserPopup();
            }
        }
    });

    // ========================================
    // FUNÇÃO GLOBAL DE FECHAR
    // ========================================
    function closeUserPopup() {
        const popup = document.getElementById("user-popup");
        if (popup) {
            popup.classList.add("hidden");
            popup.classList.remove("show");
            
            // Opcional: Remove classe expandida para próxima vez abrir pequeno
            const content = popup.querySelector(".popup-content-fullscreen");
            if(content) content.classList.remove("expanded");

            const rejectInput = document.getElementById("popup-reject-input");
            const likeInput = document.getElementById("popup-like-input");
            if(rejectInput) rejectInput.value = "";
            if(likeInput) likeInput.value = "";
        }
    }

    // 1. Evento no Botão X
    if (closePopupBtn) {
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

    // ========================================
    // 10. DRAG / SWIPE NO POPUP
    // ========================================
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

            // Se expandido e tem scroll, não arrasta se clicar no texto
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

            // Arrastando para cima (Expandir)
            if (!isExpanded() && deltaY > 0) {
                 e.preventDefault();
                 popupContent.style.height = `${startHeight + deltaY}px`;
            } 
            // Arrastando para baixo (Fechar)
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

  }); // Fim do AddEventListener DOMContentLoaded
}); // Fim do ForEach