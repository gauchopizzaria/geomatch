class Message < ApplicationRecord  
  include GlobalID::Identification

  belongs_to :match
  belongs_to :sender, class_name: "User"

  validates :content, presence: true

  # Callbacks para disparar ações após a criação da mensagem
  after_create_commit :broadcast_message
  after_create_commit :send_push_notification

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
        avatar_url: sender.avatar_url || "/assets/avatarfoto.jpg"
      }
    }

    MatchChannel.broadcast_to(match, payload)
  end

  # Envia a notificação push (para quem está com o celular bloqueado ou app fechado)
 def send_push_notification
  # Garante que estamos pegando o outro usuário do match
  recipient = (match.user_1_id == sender_id) ? match.user_2 : match.user_1
  
  # Segurança extra: não envia para si mesmo
  return if recipient.id == sender_id 

  recipient.push_subscriptions.each do |sub|
    begin
      # O segredo é passar o JSON diretamente no campo 'message'
      WebPush.payload_send(
        message: { 
          title: "GeoMatch", 
          body: "Nova mensagem de #{sender.display_name}", 
          data: { path: "/matches/#{match.id}" }
        }.to_json,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        vapid: {
          subject: 'mailto:suporte@geomtachbr.com', # Use o seu email real aqui
          public_key: ENV['VAPID_PUBLIC_KEY'],
          private_key: ENV['VAPID_PRIVATE_KEY']
        }
      )
    rescue WebPush::ExpiredSubscription
      subscription.destroy
    rescue => e
      Rails.logger.error "Erro ao enviar push: #{e.message}"
    end
  end
end
end
