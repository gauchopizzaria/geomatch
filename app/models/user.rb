class User < ApplicationRecord
  # Devise
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable


 
  # Garante que os checkboxes foram marcados no cadastro
  validates :terms_of_use, acceptance: { message: 'devem ser aceitos para prosseguir.' }
  validates :data_policy, acceptance: { message: 'deve ser aceita para prosseguir.' }       

  # --- Associações ---
  belongs_to :plan
  validates :plan, presence: true

  has_many :payments, dependent: :destroy
  has_many :likes, foreign_key: :liker_id, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  
  # Matches
  has_many :matches_as_user, class_name: 'Match', foreign_key: 'user_id', dependent: :destroy
  has_many :matches_as_matched_user, class_name: 'Match', foreign_key: 'matched_user_id', dependent: :destroy
  
  has_many :notifications, foreign_key: :recipient_id, dependent: :destroy
  has_many :stories, dependent: :destroy

  # =========================================================
  # BLOQUEIOS
  # =========================================================
  
  has_many :blocks_sent, class_name: 'Block', foreign_key: 'blocker_id', dependent: :destroy
  has_many :blocked_users, through: :blocks_sent, source: :blocked

  has_many :blocks_received, class_name: 'Block', foreign_key: 'blocked_id', dependent: :destroy
  has_many :blocked_by_users, through: :blocks_received, source: :blocker

  has_many :reports_sent, class_name: 'Report', foreign_key: :reporter_id, dependent: :destroy

  # Active Storage
  has_one_attached :avatar
  has_one_attached :verification_photo
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

  scope :visible, -> { where(invisible: [false, nil]) }
  
  # --- Callbacks ---
  after_create :attach_default_avatar
  before_validation :set_default_plan, on: :create

  # --- Métodos Públicos ---

  # =========================================================
  # REGRAS DOS PLANOS (ATUALIZADO)
  # =========================================================

  # 1. Pode usar o MODO INVISÍVEL?
  # Regra: Só Gold pode (ou se o JSON permitir explicitamente)
  def can_use_invisible_mode?
    features = (plan.features || {}).with_indifferent_access
    return true if features[:allow_invisible] == true
    
    plan.name == 'Gold'
  end

  # =========================================================
  # LÓGICA DE LIMITES (CORRIGIDA E BLINDADA)
  # =========================================================

  # 1. Verifica se pode dar LIKE
  def can_like?
    # O truque está aqui: .with_indifferent_access
    features = (plan.features || {}).with_indifferent_access

    # 1. Se for ilimitado (Plus ou Gold)
    return true if features[:likes_right_unlimited] == true

    # 2. Se tiver limite numérico (Free: 47)
    limit = features[:likes_right_limit]
    
    if limit.present?
      # Regra de Reset: 5 horas
      if last_like_reset_at.nil? || Time.current > (last_like_reset_at + 5.hours)
        reset_likes_counter!
      end
      
      # Verifica saldo atual
      return likes_count < limit.to_i
    end

    # FAILSAFE: Se o usuário é FREE e não achou limite, BLOQUEIA por padrão 47
    if plan.name == 'Free'
      return likes_count < 47
    end

    true
  end

  # 2. Incrementa o contador de LIKE
  def increment_likes!
    features = (plan.features || {}).with_indifferent_access
    
    unless features[:likes_right_unlimited] == true
      update(last_like_reset_at: Time.current) if likes_count == 0
      increment!(:likes_count)
    end
  end

  # 3. Verifica se pode enviar MENSAGEM
  def can_send_message?
    features = (plan.features || {}).with_indifferent_access
    dm_config = (features[:direct_messages] || {}).with_indifferent_access

    # --- REGRA 1: Plus e Gold são ILIMITADOS ---
    return true if ['Plus', 'Gold'].include?(plan.name)

    # --- REGRA 2: Free tem limite de 7 ---
    if plan.name == 'Free'
      limit = 7
      
      # Verifica reset (24h)
      if last_message_reset_at.nil? || Time.current > (last_message_reset_at + 24.hours)
        reset_messages_counter!
      end

      return messages_count < limit
    end

    # Fallback: Se não for nenhum dos nomes acima, usa o JSON do banco
    return false if dm_config[:enabled] == false
    return true if features[:unlimited_messages] == true || dm_config[:daily_limit].nil?

    # Limite genérico do JSON
    limit = dm_config[:daily_limit]
    if limit.present?
      if last_message_reset_at.nil? || Time.current > (last_message_reset_at + 24.hours)
        reset_messages_counter!
      end
      return messages_count < limit.to_i
    end

    true
  end

  # 4. Incrementa o contador de MENSAGEM
  def increment_messages!
    features = (plan.features || {}).with_indifferent_access
    dm_config = (features[:direct_messages] || {}).with_indifferent_access
    
    # Só incrementa se não for ilimitado (Ou seja, se for Free ou tiver limite no JSON)
    is_unlimited = ['Plus', 'Gold'].include?(plan.name) || features[:unlimited_messages] == true

    if !is_unlimited
      update(last_message_reset_at: Time.current) if messages_count == 0
      increment!(:messages_count)
    end
  end

  # =========================================================

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

  def excluded_user_ids
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

  # =========================================================
  # PERMISSÕES DE VISUALIZAÇÃO (NOTIFICAÇÕES)
  # =========================================================

  # 1. Pode ver quem curtiu ELE? (Aba "Quem te curtiu")
  # Free: Não | Plus: Sim | Gold: Sim
  def can_see_who_liked_me?
    features = (plan.features || {}).with_indifferent_access
    features[:see_who_liked_me] == true
  end

  # 2. Pode ver quem ELE curtiu? (Aba "Você curtiu")
  # Free: Não | Plus: Sim | Gold: Sim
  def can_see_who_i_liked?
    features = (plan.features || {}).with_indifferent_access
    features[:see_who_i_liked] == true
  end
  
  private

  def reset_likes_counter!
    update(likes_count: 0, last_like_reset_at: Time.current)
  end

  def reset_messages_counter!
    update(messages_count: 0, last_message_reset_at: Time.current)
  end

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