class Message < ApplicationRecord  
  include GlobalID::Identification

  belongs_to :match
  belongs_to :sender, class_name: "User"
  has_many   :reactions, dependent: :destroy

  validates :content, presence: true

  after_create_commit  :broadcast_message
  after_create_commit  :send_push_notification
  after_destroy_commit :broadcast_deletion

  private

  # Envia a mensagem em tempo real via ActionCable (para quem está com o chat aberto)
  def broadcast_message
    payload = {
      message: {
        id: id,
        content: content,
        sender_id: sender_id,
        created_at: created_at.iso8601,
        user_name: sender.display_name || "Usuário",
        avatar_url: sender.avatar_url || "/assets/avatarfoto.jpg",
        verified:   sender.verified?
      }
    }

    MatchChannel.broadcast_to(match, payload)
  end

  def broadcast_deletion
    MatchChannel.broadcast_to(match, { deleted_message_id: id })
  end

  def send_push_notification
    PushNotificationJob.perform_later(id)
  end
end
