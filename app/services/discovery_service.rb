  # app/services/discovery_service.rb
  class DiscoveryService
    include Rails.application.routes.url_helpers
    def initialize(user)
      @user = user
    end

    # O método agora aceita o raio dinâmico e o filtro de gênero
 def find_nearby_users(radius_km = 10, gender_filter = nil)
  return [] unless @user.latitude && @user.longitude

  query = User.near([@user.latitude, @user.longitude], radius_km)
              .where.not(id: @user.id)
              .where(invisible: [false, nil])

  # 2. Filtro de gênero com suporte a variações de escrita
  if gender_filter.present? && gender_filter != "all"
    # Mapeamos o valor do JS para o valor base que buscaremos no banco
    mapping = {
      "male"       => "homem",
      "female"     => "mulher",
      "non-binary" => "não binário"
    }
    
    target_value = mapping[gender_filter]

    if target_value
      # Usamos LOWER(gender) para ignorar se está "Homem" ou "homem" no banco
      query = query.where("LOWER(gender) = ?", target_value)
    end
  end

  # 3. Mapeia para JSON (mantenha o restante do seu código igual)
  query.map do |u|
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
      bio: u.bio,
      interested_in: u.interested_in,
      hobbies_list: u.hobbies_list,
      avatar_url: (u.avatar.attached? ? Rails.application.routes.url_helpers.rails_blob_path(u.avatar, only_path: true) : nil),
      distance_km: distance
    }
  end
end
  end