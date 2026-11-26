# "Agradecer a Fulano" na tela do mimo recebido (pages/mimo_celebration).
#
# A mensagem vai para a conversa de vocês: se ainda não existe conversa, ela é criada
# (quem mandou o mimo puxou o assunto). Não cria quando um bloqueou o outro, nem quando
# quem mandou o mimo já tinha desfeito o match. Cada mimo pode ser agradecido uma vez —
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
    return refuse("Não é possível enviar mensagem para essa pessoa.") unless can_talk_to?(sender)

    match = nil
    ActiveRecord::Base.transaction do
      mimo.lock!
      raise ActiveRecord::RecordNotUnique, "já agradecido" if mimo.thanked?

      match = conversation_with(sender) || Match.create!(user: sender, matched_user: current_user)
      match.messages.create!(sender: current_user, content: text)
      mimo.update!(thanked_at: Time.current)
    end

    render json: { status: "sent", match_url: match_path(match) }, status: :created
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

  def conversation_with(user)
    Match.for_user(current_user.id).where("user_id = :id OR matched_user_id = :id", id: user.id).first
  end

  # Bloqueio (dos dois lados) impede; e se quem mandou o mimo desfez o match com você
  # (a curtida dele virou "agora não"), a conversa não é recriada à força
  def can_talk_to?(user)
    return false if user.nil? || current_user.excluded_user_ids.include?(user.id)
    return true if conversation_with(user)

    !Like.exists?(liker_id: user.id, liked_id: current_user.id, is_like: false)
  end
end
