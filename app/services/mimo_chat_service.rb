# Mimos na conversa do chat.
#
#   MimoChatService.post_gift(mimo)
#     Depois que o mimo é pago: põe o balão "Mimo" na conversa de quem enviou com quem
#     recebeu (mensagem de quem enviou, apontando para o mimo). Sem conversa ainda, ela
#     é aberta — o mimo puxa o assunto.
#
#   MimoChatService.post_thanks(mimo, text)
#     "Agradecer" na tela do mimo recebido: a mensagem de quem recebeu vai para a mesma
#     conversa, apontando para o mimo (o balão cita "Agradeceu pelo mimo: …").
#
# Uma conversa nova não é aberta quando um bloqueou o outro, nem quando quem vai
# receber a mensagem tinha dispensado quem escreve (curtida "agora não" / match
# desfeito). O mimo continua entregue (carteira + notificação), só não vira conversa.
class MimoChatService
  class NotAllowedError < StandardError; end

  def self.enabled?
    Message.mimo_messages?
  end

  # Não levanta erro: o mimo já foi pago e entregue; o balão na conversa é um extra
  def self.post_gift(mimo)
    return nil unless enabled? && mimo&.completed? && mimo.receiver

    match = open_conversation(from: mimo.sender, to: mimo.receiver)
    return nil unless match
    return existing_gift(match, mimo) if existing_gift(match, mimo)

    match.messages.create!(sender: mimo.sender, mimo_transaction: mimo, content: gift_label(mimo))
  rescue StandardError => e
    Rails.logger.error "[MimoChatService.post_gift] mimo=#{mimo&.id}: #{e.class}: #{e.message}"
    nil
  end

  # Levanta NotAllowedError quando a conversa não pode ser aberta
  def self.post_thanks(mimo, text)
    match = open_conversation(from: mimo.receiver, to: mimo.sender)
    raise NotAllowedError, "Não é possível enviar mensagem para essa pessoa." unless match

    attrs = { sender: mimo.receiver, content: text }
    attrs[:mimo_transaction] = mimo if enabled?
    match.messages.create!(attrs)
  end

  # Conversa entre as duas pessoas; abre uma nova se for permitido. nil = não pode.
  def self.open_conversation(from:, to:)
    return nil if from.nil? || to.nil? || from.id == to.id
    return nil if from.excluded_user_ids.include?(to.id)

    conversation_between(from, to) || begin
      return nil if Like.exists?(liker_id: to.id, liked_id: from.id, is_like: false)

      Match.create!(user: from, matched_user: to)
    end
  end

  def self.conversation_between(a, b)
    Match.for_user(a.id).where("user_id = :id OR matched_user_id = :id", id: b.id).first
  end

  # "🎁 Mimo: Rosa vermelha" — o que a lista de conversas e o push mostram
  def self.gift_label(mimo)
    "🎁 Mimo: #{mimo.display_label}"
  end

  def self.existing_gift(match, mimo)
    match.messages.find_by(mimo_transaction_id: mimo.id, sender_id: mimo.sender_id)
  end
  private_class_method :existing_gift
end
