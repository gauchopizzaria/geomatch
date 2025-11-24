class User < ApplicationRecord
  # Devise modules
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Avatar (Active Storage)
  has_one_attached :avatar

  # Geocoder (para localização)
  geocoded_by :address
  after_validation :geocode, if: ->(obj) { obj.address.present? && obj.will_save_change_to_address? }

  # Relacionamentos
  has_many :likes, foreign_key: :liker_id, dependent: :destroy
  has_many :matches_as_user, class_name: 'Match', foreign_key: 'user_id', dependent: :destroy
  has_many :matches_as_matched_user, class_name: 'Match', foreign_key: 'matched_user_id', dependent: :destroy
  has_many :messages, through: :matches_as_user

  # Método para buscar todos os matches do usuário (como user OU matched_user)
  def matches
    Match.where("user_id = ? OR matched_user_id = ?", id, id)
  end

  def display_name
   username.presence || email&.split('@')&.first || "Usuário"
  end

  # Para tratar hobbies como array
  def hobbies_list
    (hobbies || "").split(",")
  end

  def hobbies_list=(values)
    self.hobbies = values.reject(&:blank?).join(",")
  end

end
