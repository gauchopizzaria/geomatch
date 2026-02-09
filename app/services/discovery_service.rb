  # app/services/discovery_service.rb
  class DiscoveryService
    include Rails.application.routes.url_helpers
    def initialize(user)
      @user = user
    end

    # O método agora aceita o raio dinâmico e o filtro de gênero
    def find_nearby_users(radius_km = 10, gender_filter = nil)
      return [] unless @user.latitude && @user.longitude

      # 1. Inicia a query com a busca de usuários próximos dentro do raio definido
      query = User.near([@user.latitude, @user.longitude], radius_km)
                  .where.not(id: @user.id)
                  .where(invisible: [false, nil])
      # 2. Aplica o filtro de gênero se for diferente de 'all' ou nil
      if gender_filter.present? && gender_filter != "all"
        # Assumindo que o campo 'gender' no banco de dados armazena 'male' ou 'female'
        query = query.where(gender: gender_filter)
      end

      # 3. Mapeia os resultados para o formato JSON
query.map do |u|
  # Recalcula a distância para garantir precisão
  distance = Geocoder::Calculations.distance_between(
    [@user.latitude, @user.longitude],
    [u.latitude, u.longitude]
  ).round(1)

  {
    id: u.id,
    username: u.username,
    latitude: u.latitude,
    longitude: u.longitude,
    gender: u.gender, 
    city: u.city,
    # --- ADICIONE ESTAS LINHAS ABAIXO ---
    bio: u.bio,
    interested_in: u.interested_in,
    hobbies_list: u.hobbies_list,
    # ------------------------------------
    avatar_url: (u.avatar.attached? ? Rails.application.routes.url_helpers.rails_blob_url(u.avatar, only_path: true) : nil),
    distance_km: distance
  }
end
    end
  end