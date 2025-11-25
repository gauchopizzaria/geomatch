# app/services/discovery_service.rb
class DiscoveryService
  include Rails.application.routes.url_helpers
  def initialize(user)
    @user = user
  end

  def find_nearby_users(radius_km = 10)
    return [] unless @user.latitude && @user.longitude

    User.near([@user.latitude, @user.longitude], radius_km)
        .where.not(id: @user.id)
        .map do |u|
          distance = Geocoder::Calculations.distance_between(
            [@user.latitude, @user.longitude],
            [u.latitude, u.longitude]
          ).round(1)

          {
            id: u.id,
            username: u.username,
            latitude: u.latitude,
            longitude: u.longitude,
            avatar_url: (u.avatar.attached? ? Rails.application.routes.url_helpers.rails_blob_url(u.avatar, only_path: true) : nil),
            distance_km: distance
          }
        end
  end
end
