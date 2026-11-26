# "Agradecer a Fulano" na tela do mimo recebido (pages/mimo_celebration).
#
# A mensagem vai para a conversa de vocês, citando o mimo ("Agradeceu pelo mimo: …" no
# balão) — ver MimoChatService.post_thanks. Sem conversa ainda, ela é criada (quem
# mandou o mimo puxou o assunto); não cria quando um bloqueou o outro, nem quando quem
# mandou o mimo já tinha desfeito o match. Cada mimo pode ser agradecido uma vez —
# depois o botão vira "Agradecimento enviado".
class MimoThanksController < ApplicationController
  before_action :authenticate_user!

  MESSAGE_MAX = 200

  # POST /mimos/recebido/:id/agradecer  { message: "Muito obrigado! 🥰 ..." }
  def create
    mimo   = current_user.mimo_transactions_received.completed.find(params[:id])
    sender = mimo.sender
    text   = params[:message].to_s.strip

    return refuse("Você já agradeceu este mimo.") if mimo.thanked?
    return refuse("Escreva uma mensagem de agradecimento.") if text.empty?
    return refuse("A mensagem pode ter até #{MESSAGE_MAX} caracteres.") if text.length > MESSAGE_MAX
    return refuse("Não é possível enviar mensagem para essa pessoa.") if sender.nil?

    message = nil
    ActiveRecord::Base.transaction do
      mimo.lock!
      raise ActiveRecord::RecordNotUnique, "já agradecido" if mimo.thanked?

      message = MimoChatService.post_thanks(mimo, text)
      mimo.update!(thanked_at: Time.current)
    end

    render json: { status: "sent", match_url: match_path(message.match_id) }, status: :created
  rescue MimoChatService::NotAllowedError => e
    refuse(e.message)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Mimo não encontrado." }, status: :not_found
  rescue ActiveRecord::RecordNotUnique
    refuse("Você já agradeceu este mimo.")
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[MimoThanksController] mimo=#{params[:id]} user=#{current_user.id}: #{e.message}"
    refuse("Não foi possível enviar o agradecimento agora.")
  end

  private

  def refuse(text)
    render json: { error: text }, status: :unprocessable_entity
  end
end
