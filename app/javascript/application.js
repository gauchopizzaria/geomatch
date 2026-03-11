import "@hotwired/turbo-rails"; // Turbo Rails para navegação sem recarregar
import "./controllers";        // Carrega os controllers do Stimulus
import "./map";                // O arquivo JavaScript do mapa, se necessárioimport "channels"
import "./confetti_animation";
import "./chat_logic";
import "./stories";
import "trix";
import "@rails/actiontext";
import "./dark_mode_toggle";
import "./push_notifications"; // Importa o arquivo de notificações push
import L from "leaflet";
window.L = L; // Isso garante que o plugin encontre o 'L' global
import "leaflet.markercluster"; // Importe o plugin LOGO DEPOIS do window.L
import "./live_location"; // Importa o módulo de rastreamento contínuo
import "./map_3d"; // Importa o módulo do mapa 3D (Mapbox GL JS)