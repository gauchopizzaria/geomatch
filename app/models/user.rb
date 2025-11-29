class User < ApplicationRecord
  # Devise modules
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Avatar (Active Storage)
  has_one_attached :avatar

  # Geocoder (para localização)
  geocoded_by :address
  after_validation :geocode, if: ->(obj) { obj.address.present? && obj.will_save_change_to_address? }

  # ==========================
  #  AVATAR DEFAULT
  # ==========================

  # 1️⃣ Método geral para views: sempre retorna algo exibível
  def avatar_or_default
    if avatar.attached?
      avatar
    else
      "/assets/avatarfoto.jpg" # arquivo em app/assets/images
    end
  end

  # 2️⃣ Método para API JSON / Nearby
  def avatar_url
    if avatar.attached?
      Rails.application.routes.url_helpers.url_for(avatar)
    else
      ActionController::Base.helpers.asset_path("avatarfoto.jpg")
    end
  end

  # 3️⃣ Aplica AUTOMATICAMENTE um avatar padrão ao criar usuário
  after_create :attach_default_avatar

  def attach_default_avatar
    return if avatar.attached?

    default_path = Rails.root.join("app/assets/images/avatarfoto.jpg")

    if File.exist?(default_path)
      avatar.attach(
        io: File.open(default_path),
        filename: "avatarfoto.jpg",
        content_type: "image/jpeg"
      )
    else
      Rails.logger.error "⚠️ ERRO: avatarfoto.jpg não encontrado em app/assets/images"
    end
  end

  # ==========================
  #  RELACIONAMENTOS
  # ==========================

  has_many :likes, foreign_key: :liker_id, dependent: :destroy
  has_many :matches_as_user, class_name: 'Match', foreign_key: 'user_id', dependent: :destroy
  has_many :matches_as_matched_user, class_name: 'Match', foreign_key: 'matched_user_id', dependent: :destroy
  has_many :messages, through: :matches_as_user
  has_many :notifications, foreign_key: :recipient_id, dependent: :destroy

  # Matches unificados
  def matches
    Match.where("user_id = ? OR matched_user_id = ?", id, id)
  end

  # Nome para exibição
  def display_name
    username.presence || email&.split('@')&.first || "Usuário"
  end

  # ==========================
  #  HOBBIES
  # ==========================

  def hobbies_list
    (hobbies || "").split(",")
  end

  def hobbies_list=(values)
    self.hobbies = values.reject(&:blank?).join(",")
  end
end
