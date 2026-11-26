# app/jobs/notification_broadcast_job.rb
class NotificationBroadcastJob < ApplicationJob
  queue_as :default

  # Curtida desfeita dentro da janela (Like::UNDO_WINDOW): a notificação foi apagada antes
  # de o job rodar — não há o que enviar
  discard_on ActiveJob::DeserializationError

  # Avisa o navegador de quem recebeu: o número de "Te curtiram" (a mesma regra da lista)
  # e o tipo. Antes renderizava o card da aba aqui — o card usa current_user, que não
  # existe num job, e o envio falhava; o app web nem escutava o canal.
  def perform(notification)
    recipient = notification.recipient
    return unless recipient

    payload = {
      kind:  notification.notifiable_type.to_s.underscore, # like / match / mimo_transaction
      count: recipient.unseen_likes_count
    }
    # Mimo recebido com o app aberto: o aviso no topo leva à tela "Você ganhou um mimo"
    if notification.notifiable.is_a?(MimoTransaction)
      payload[:url]   = Rails.application.routes.url_helpers.mimo_celebration_page_path(notification.notifiable_id)
      payload[:title] = "#{notification.actor&.display_name} te enviou um mimo 🎁"
    end

    NotificationChannel.broadcast_to(recipient, **payload)
  end
end
