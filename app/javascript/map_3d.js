const mapboxToken = document.querySelector('meta[name="mapbox-token"]').content;
mapboxgl.accessToken = mapboxToken;

document.addEventListener("turbo:load", () => {
  const mapElement = document.getElementById('map-3d');
  if (!mapElement) return;

  // 1. INICIALIZAÇÃO DO MAPA 3D
const map = new mapboxgl.Map({
  container: 'map-3d',
  // O estilo Standard é o segredo para o realismo
  style: 'mapbox://styles/mapbox/standard', 
  center: [-39.2781, -14.7876],
  zoom: 16.5,
  pitch: 75, // Aumente a inclinação para ver o horizonte e o céu
  bearing: -20,
  antialias: true
});

map.on('style.load', () => {
  // 1. Configura as opções do Estilo Standard (Árvores e Prédios)
  map.setConfigProperty('basemap', 'show3dObjects', true); 
  map.setConfigProperty('basemap', 'show3dTrees', true);
  map.setConfigProperty('basemap', 'lightPreset', 'day');
  
  // 2. Adiciona o Terreno 3D (Montanhas e Elevações)
  map.addSource('mapbox-dem', {
    'type': 'raster-dem',
    'url': 'mapbox://mapbox.mapbox-terrain-dem-v1',
    'tileSize': 512,
    'maxzoom': 14
  });
  
  map.setTerrain({ 'source': 'mapbox-dem', 'exaggeration': 1.5 });

  // 3. Adiciona o Céu e Atmosfera (Gera o degradê do horizonte)
  map.setFog({
    'range': [0.5, 10],
    'color': '#f8f0e3', // Cor levemente amarelada para o "Golden Hour"
    'horizon-blend': 0.1
  });


  // OPCIONAL: Adicionar uma camada de grama/verde mais vibrante
  map.setPaintProperty('landuse', 'fill-color', '#e8f5e9');
});

  // 3. ADAPTANDO A BUSCA DE USUÁRIOS (NEARBY)
  // Você vai usar a mesma rota /users/nearby que já está nas suas routes.rb
  async function fetchUsers3D() {
    const resp = await fetch(`/users/nearby?latitude=${map.getCenter().lat}&longitude=${map.getCenter().lng}&range=300`);
    const users = await resp.json();
    
    users.forEach(user => {
      // Criar elemento do marcador (Aura Dourada)
      const el = document.createElement('div');
      el.className = 'custom-marker'; 
      el.innerHTML = `<div class="avatar-frame-wrapper">
                        <img src="${user.avatar_url}" class="avatar-user-img">
                      </div>`;

      // Adicionar marcador ao Mapbox
      new mapboxgl.Marker(el)
        .setLngLat([user.longitude, user.latitude])
        .addTo(map);

      // Evento de clique para abrir o seu Popup (o mesmo do discover normal)
      el.addEventListener('click', () => showUserPopup(user));
    });
  }

  map.on('load', fetchUsers3D);
});

function addUserMarker(user) {
  const el = document.createElement('div');
  el.className = 'floating-marker'; // Nova classe CSS
  el.innerHTML = `
    <div class="marker-content">
      <img src="${user.avatar_url}" />
      <div class="online-badge"></div>
    </div>
    <div class="marker-shadow"></div>
  `;

  new mapboxgl.Marker(el)
    .setLngLat([user.longitude, user.latitude])
    .addTo(map);
}
