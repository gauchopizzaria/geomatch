class User < ApplicationRecord
  # Devise
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # --- Associações ---
  belongs_to :plan
  validates :plan, presence: true

  has_many :payments, dependent: :destroy
  has_many :likes, foreign_key: :liker_id, dependent: :destroy
  
  # Matches
  has_many :matches_as_user, class_name: 'Match', foreign_key: 'user_id', dependent: :destroy
  has_many :matches_as_matched_user, class_name: 'Match', foreign_key: 'matched_user_id', dependent: :destroy
  
  has_many :notifications, foreign_key: :recipient_id, dependent: :destroy
  has_many :stories, dependent: :destroy

  # =========================================================
  # BLOQUEIOS (AQUI ESTÁ A LÓGICA CORRIGIDA)
  # =========================================================
  
  # 1. Quem EU bloqueiei (Active Record vai buscar na tabela 'blocks' onde blocker_id sou eu)
  has_many :blocks_sent, class_name: 'Block', foreign_key: 'blocker_id', dependent: :destroy
  
  # A relação :blocked_users usa 'source: :blocked'. 
  # Isso só funciona porque no Passo 1 definimos 'belongs_to :blocked' no model Block.
  has_many :blocked_users, through: :blocks_sent, source: :blocked
  
  # 2. Quem ME bloqueou (Active Record vai buscar na tabela 'blocks' onde blocked_id sou eu)
  has_many :blocks_received, class_name: 'Block', foreign_key: 'blocked_id', dependent: :destroy
  has_many :blocked_by_users, through: :blocks_received, source: :blocker

  # Active Storage
  has_one_attached :avatar
  has_many_attached :album_photos 

  # Geocoder
  geocoded_by :address
  after_validation :geocode, if: ->(obj) { obj.address.present? && obj.will_save_change_to_address? }

  # --- Scopes ---
  scope :expired_premium, -> { 
    free_plan = Plan.find_by(name: 'Free')
    return none unless free_plan
    where.not(plan_id: free_plan.id).where('premium_until < ?', Time.current) 
  }
  
  scope :filter_by_age, ->(min, max) {
    return all if min.blank? || max.blank?
    start_date = (max.to_i + 1).years.ago.to_date + 1.day
    end_date   = min.to_i.years.ago.to_date
    where(birthdate: start_date..end_date)
  }

  # --- Callbacks ---
  after_create :attach_default_avatar
  before_validation :set_default_plan, on: :create

  # --- Métodos Públicos ---

  def downgrade_to_free!
    free_plan = Plan.find_by(name: 'Free')
    return unless free_plan
    transaction do
      update!(plan: free_plan, premium_until: nil)
    end
  end

  def avatar_or_default
    avatar.attached? ? avatar : "avatarfoto.jpg"
  end

  def avatar_url
    if avatar.attached?
      Rails.application.routes.url_helpers.url_for(avatar)
    else
      ActionController::Base.helpers.asset_path("avatarfoto.jpg")
    end
  end

  def matches
    Match.where("user_id = ? OR matched_user_id = ?", id, id)
  end

  # ESTE MÉTODO AGORA FUNCIONARÁ SEM ERROS
  def excluded_user_ids
    # Pega os IDs de quem eu bloqueiei + IDs de quem me bloqueou
    blocked_users.pluck(:id) + blocked_by_users.pluck(:id)
  end

  def display_name
    username.presence || email&.split('@')&.first || "Usuário"
  end
  
  def age
    return nil unless birthdate
    today = Date.current
    age_calc = today.year - birthdate.year
    age_calc -= 1 if today < birthdate + age_calc.years
    age_calc
  end

  def city
    return nil if address.blank?
    address.split(",").last&.strip
  end

  def hobbies_list
    (hobbies || "").split(",")
  end

  def hobbies_list=(values)
    val_to_save = values.is_a?(String) ? values.split(',') : values
    self.hobbies = val_to_save.reject(&:blank?).join(",")
  end

  def online?
    last_seen_at.present? && last_seen_at > 2.minutes.ago
  end

  def premium?
    premium_until.present? && premium_until > Time.current
  end
  
  private

  def attach_default_avatar
    return if avatar.attached?
    default_path = Rails.root.join("app/assets/images/avatarfoto.jpg")

    if File.exist?(default_path)
      avatar.attach(io: File.open(default_path), filename: "avatarfoto.jpg", content_type: "image/jpeg")
    else
      Rails.logger.error "⚠️ ERRO: avatarfoto.jpg não encontrado em app/assets/images"
    end
  end

  def set_default_plan
    self.plan ||= Plan.find_by(name: "Free") 
  end
end