import L from "leaflet";
import "leaflet.markercluster"; // Importa a biblioteca de clusterização

// Garante compatibilidade com Turbo e DOM normal
["DOMContentLoaded", "turbo:load"].forEach((evt) => {
  document.addEventListener(evt, async () => {
    const mapContainer = document.getElementById("map");
    if (!mapContainer) {
      console.error("❌ Elemento #map não encontrado no DOM.");
      return;
    }

    // Define a localização padrão (Itabuna) caso a geolocalização falhe
    const defaultLat = -14.788;
    const defaultLng = -39.278;
    const defaultZoom = 13;

    const map = L.map("map").setView([defaultLat, defaultLng], defaultZoom); // Itabuna como base

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "© OpenStreetMap",
    } ).addTo(map);

    // Obtém localização atual e envia para backend
    navigator.geolocation.getCurrentPosition(async (position) => {
      const { latitude, longitude } = position.coords;

      // 🎯 CORREÇÃO 1: Centraliza o mapa na localização do usuário
      map.setView([latitude, longitude], 13);

      // Atualiza backend
      await fetch(`/users/nearby?latitude=${latitude}&longitude=${longitude}`);
      loadNearbyUsers();
    }, (error) => {
      console.error("Erro ao obter localização:", error);
      // Se falhar, carrega usuários com a localização padrão (Itabuna)
      loadNearbyUsers();
    });

    async function loadNearbyUsers() {
      const response = await fetch("/users/nearby");
      const users = await response.json();

      // 🎯 CORREÇÃO 3: Implementa Marker Clustering para lidar com usuários no mesmo local
      const markers = L.markerClusterGroup();

      users.forEach((user) => {
        const icon = L.divIcon({
          html: `<img src="${user.avatar_url || '/default-avatar.png'}" class="marker-avatar">`,
          className: "custom-marker",
          iconSize: [40, 40],
        });

        const marker = L.marker([user.latitude, user.longitude], { icon });

        // Adiciona um popup simples para o caso de clique em um único marcador
        marker.bindPopup(`<b>${user.username}</b>  
${user.city}`);

        marker.on("click", () => {
          showUserPopup(user);
        });

        markers.addLayer(marker);
      });

      map.addLayer(markers);

      // === NOVO: renderiza usuários reais na sidebar lateral ===
      const listContainer = document.getElementById("users-list");
      if (listContainer) {
        listContainer.innerHTML = ""; // limpa lista anterior

        users.forEach((user) => {
          const li = document.createElement("li");
          li.innerHTML = `
            <img src="${user.avatar_url || '/default-avatar.png'}" alt="${user.username || 'Usuário'}" class="avatar">
            <span>${user.username || "Usuário"} ${
            user.distance_km ? `(${user.distance_km} km)` : ""
          }</span>
          `;

          li.addEventListener("click", () => {
            map.setView([user.latitude, user.longitude], 15);
            showUserPopup(user);
          });

          listContainer.appendChild(li);
        });
      }

      // 🔹 Emite evento para o HTML saber que os usuários foram carregados
      document.dispatchEvent(new CustomEvent('usersLoaded', { detail: users }));
    }

    function showUserPopup(user) {
      const popup = document.getElementById("user-popup");
      const avatar = document.getElementById("popup-avatar");
      const username = document.getElementById("popup-username");
      const location = document.getElementById("popup-location");
      const distance = document.getElementById("popup-distance");

      // Armazena o ID do usuário atual no popup
      popup.dataset.userId = user.id;

      // Atualiza informações
      avatar.src = user.avatar_url || "/default-avatar.png";
      username.textContent = user.username || "Usuário desconhecido";
      location.textContent = user.city || "Localização não informada";
      distance.textContent = user.distance_km
        ? `a ~${user.distance_km} km de você`
        : "";

      popup.classList.remove("hidden");
      popup.classList.add("show");
    }

    // === Listener do botão de curtir ===
    document.addEventListener("click", async (e) => {
      if (e.target && e.target.id === "like-btn") {
        const popup = document.getElementById("user-popup");
        const likedUserId = popup.dataset.userId;

        if (!likedUserId) return;

        try {
          const token = document
            .querySelector('meta[name="csrf-token"]')
            .getAttribute("content");

          const response = await fetch("/likes", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-CSRF-Token": token,
            },
            body: JSON.stringify({ user_id: likedUserId }),
          });

          if (response.ok) {
            const data = await response.json();
            if (data.status === "already_liked") {
              alert("Você já curtiu este usuário. Não é possível curtir duas vezes."); // 🎯 CORREÇÃO 2: Trata o 'already_liked'
            } else if (data.message === "💘 Deu match!") {
              alert("🎉 MATCH! Vocês se curtiram!");
            } else {
              alert("❤️ Curtida enviada!");
            }
          } else {
            const data = await response.json().catch(() => ({}));
            alert(`Erro ao curtir: ${data.error || response.statusText}`);
          }
        } catch (error) {
          console.error("Erro ao enviar curtida:", error);
          alert("⚠️ Falha ao enviar curtida. Verifique o console.");
        }
      }
    });
  });
});

// Estilo do marcador com avatar circular (mantido no JS para compatibilidade com o Leaflet.divIcon)
const style = document.createElement("style");
style.textContent = `
  .marker-avatar {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    border: 3px solid #d4af37; /* Cor primária */
    object-fit: cover;
  }
`;
document.head.appendChild(style);
