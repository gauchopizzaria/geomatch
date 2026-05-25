# app/services/discovery_service.rb
class DiscoveryService
  include Rails.application.routes.url_helpers

  def initialize(user)
    @user = user
  end

  def find_nearby_users(radius_km = 10, gender_filter = nil)
    return [] unless @user.latitude && @user.longitude

    # Só retorna utilizadores que estão online (ativos nos últimos 5 min).
    # Quem fechar o app sem logout desaparece após 5 min de inatividade.
    # Bloqueios breves de ecrã sobrevivem porque o presence.js re-bate ao desbloquear.
    query = User.near([@user.latitude, @user.longitude], radius_km)
                .online_on_map
                .where.not(id: @user.id)
                .where(invisible: [false, nil])
                .with_attached_avatar
                .with_attached_album_photos

    if gender_filter.present? && gender_filter != "all"
      mapping = {
        "male"       => "homem",
        "female"     => "mulher",
        "non-binary" => "não binário"
      }
      
      target_value = mapping[gender_filter]

      if target_value
        query = query.where("LOWER(gender) = ?", target_value)
      end
    end

    query.map do |u|
      distance = Geocoder::Calculations.distance_between(
        [@user.latitude, @user.longitude],
        [u.latitude, u.longitude]
      ).round(3)  # 3 casas = precisão de ~1m; .round(1) truncava 70m→0.1km, quebrando filtros curtos

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
        distance_km: distance,
        last_seen_at: u.last_seen_at,
        verified: u.verified,
        photos_urls: build_photos_urls(u),
        age: u.birthdate.present? ? ((Date.today - u.birthdate.to_date) / 365.25).floor : nil
      }
    end
  end

  private

  def build_photos_urls(user)
    urls = []
    urls << rails_blob_path(user.avatar, only_path: true) if user.avatar.attached?
    user.album_photos.each { |p| urls << rails_blob_path(p, only_path: true) }
    urls
  end
end