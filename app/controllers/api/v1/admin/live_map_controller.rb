module Api
  module V1
    module Admin
      # GET /api/v1/admin/live_map
      # JSON leve: sem nomes ou fotos para o mapa carregar rápido.
      class LiveMapController < BaseController
        def index
          # Apenas usuários com coordenadas conhecidas
          @users = User
            .where.not(latitude: nil, longitude: nil)
            .select(:id, :latitude, :longitude, :last_seen_at, :invisible, :banned_at)
        end
      end
    end
  end
end
