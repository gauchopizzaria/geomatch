class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :plan
  validates :plan, presence: true
  has_many :payments, dependent: :destroy
  has_many :likes, foreign_key: :liker_id, dependent: :destroy
  has_many :matches_as_user, class_name: 'Match', foreign_key: 'user_id', dependent: :destroy
  has_many :matches_as_matched_user, class_name: 'Match', foreign_key: 'matched_user_id', dependent: :destroy
  has_many :messages, through: :matches_as_user
  has_many :notifications, foreign_key: :recipient_id, dependent: :destroy
  has_many :stories, dependent: :destroy

  has_one_attached :avatar
  has_many_attached :album_photos 

  geocoded_by :address
  after_validation :geocode, if: ->(obj) { obj.address.present? && obj.will_save_change_to_address? }

  scope :expired_premium, -> { 
    free_plan = Plan.find_by(name: 'Free')
    return none unless free_plan

    where.not(plan_id: free_plan.id)
    .where('premium_until < ?', Time.current) 
  }

  def downgrade_to_free!
    free_plan = Plan.find_by(name: 'Free')
    return unless free_plan

    transaction do
      update!(
        plan: free_plan,
        premium_until: nil
      )
    end
  end

  def avatar_or_default
    if avatar.attached?
      avatar
    else
      "/assets/avatarfoto.jpg"
    end
  end

  def avatar_url
    if avatar.attached?
      Rails.application.routes.url_helpers.url_for(avatar)
    else
      ActionController::Base.helpers.asset_path("avatarfoto.jpg")
    end
  end

  after_create :attach_default_avatar
  before_validation :set_default_plan, on: :create

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

  def matches
    Match.where("user_id = ? OR matched_user_id = ?", id, id)
  end

  def display_name
    username.presence || email&.split('@')&.first || "Usuário"
  end
  
  def age
    return nil unless birthdate

    today = Date.current
    age = today.year - birthdate.year
    age -= 1 if today < birthdate + age.years
    age
  end

  def city
    return nil if address.blank?

    address.split(",").last&.strip
  end

  def hobbies_list
    (hobbies || "").split(",")
  end

  def hobbies_list=(values)
    self.hobbies = values.reject(&:blank?).join(",")
  end

  def online?
    last_seen_at.present? && last_seen_at > 2.minutes.ago
  end

  def premium?
    premium_until.present? && premium_until > Time.current
  end

  private

  def set_default_plan
    self.plan ||= Plan.find_by(code: "free")
  end
end
