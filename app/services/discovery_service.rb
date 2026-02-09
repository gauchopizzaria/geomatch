# app/services/discovery_service.rb
class DiscoveryService
  include Rails.application.routes.url_helpers

  def initialize(user)
    @user = user
  end

  def find_nearby_users(radius_km = 10, gender_filter = nil)
    return [] unless @user.latitude && @user.longitude

    query = User.near([@user.latitude, @user.longitude], radius_km)
                .where.not(id: @user.id)
                .where(invisible: [false, nil])

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
        distance_km: distance,
        last_seen_at: u.last_seen_at # Adição crucial para o status online
      }
    end
  end
end