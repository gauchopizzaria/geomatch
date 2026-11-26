class Message < ApplicationRecord
  include GlobalID::Identification

  enum :status, { sent: 0, delivered: 1, read: 2 }, default: :sent

  # Tamanho do trecho da mensagem citada (balão e barra "Respondendo a…").
  REPLY_PREVIEW_LENGTH = 120

  # "Editar" a própria mensagem: até 15 min depois de enviar (como no WhatsApp)
  EDIT_WINDOW = 15.minutes
  # "Apagar para todos": enquanto não foi vista, ou até 3 min depois de vista
  DELETE_FOR_EVERYONE_WINDOW = 3.minutes

  # Colunas do chat novo (migration AddChatControls). Em produção o banco é
  # ajustado à mão: até elas existirem o chat segue funcionando, só sem editar
  # e sem "apagar para mim".
  def self.chat_controls?
    (%w[edited_at hidden_for_user_ids] - column_names).empty?
  end

  # Coluna dos mimos na conversa (migration AddMimoTransactionToMessages). Mesmo cuidado
  # do chat_controls?: sem ela o chat funciona, só sem o balão do mimo.
  def self.mimo_messages?
    column_names.include?("mimo_transaction_id")
  end

  # Mensagens que a pessoa não apagou para si ("Apagar para mim" / "Limpar conversa")
  scope :visible_to, ->(user) {
    chat_controls? ? where.not("? = ANY(messages.hidden_for_user_ids)", user.id) : all
  }

  belongs_to :match
  belongs_to :sender, class_name: "User"
  # Mensagem respondida (arrastar para a direita no chat). Se a original for
  # apagada, o banco zera esta coluna (on_delete: :nullify).
  belongs_to :reply_to, class_name: "Message", optional: true
  has_many   :reactions, dependent: :destroy
  # Mimo na conversa (MimoChatService): o balão do mimo (mensagem de quem enviou) ou o
  # agradecimento (mensagem de quem recebeu, que cita o mimo)
  belongs_to :mimo_transaction, optional: true

  # Mensagem de voz e foto: anexos do Active Storage + rótulo no content
  include MessageMedia

  validates :content, presence: true
  validate  :reply_to_must_belong_to_same_match

  after_create_commit  :broadcast_message
  # O balão do mimo não manda o push de mensagem: o push "te enviou um Mimo" já sai
  # pelo MimoPushNotificationJob
  after_create_commit  :send_push_notification, unless: :mimo_gift?
  after_destroy_commit :broadcast_deletion

  def edited?
    has_attribute?(:edited_at) && edited_at.present?
  end

  # Áudio, foto e o balão do mimo não têm texto para editar (o content é só o rótulo)
  def editable_by?(user)
    Message.chat_controls? && sender_id == user&.id && created_at > EDIT_WINDOW.ago && !media? && !mimo_gift?
  end

  # Só quem enviou; mensagem lida antes de existir read_at conta como vista há
  # muito tempo (não dá mais para apagar para todos). O balão do mimo fica: o mimo já
  # foi entregue (dá para "apagar para mim").
  def deletable_for_everyone_by?(user)
    return false unless sender_id == user&.id
    return false if mimo_gift?
    return true unless read?

    read_at.present? && read_at > DELETE_FOR_EVERYONE_WINDOW.ago
  end

  def edit!(new_content)
    update!(content: new_content, edited_at: Time.current)
    broadcast_edit
  end

  # "Apagar para mim": some só para quem pediu
  def hide_for!(user)
    return false unless Message.chat_controls?

    Message.where(id: id).hide_for_all!(user)
    true
  end

  def self.hide_for_all!(user)
    where.not("? = ANY(messages.hidden_for_user_ids)", user.id)
      .update_all([ "hidden_for_user_ids = array_append(hidden_for_user_ids, ?)", user.id ])
  end

  # Resposta a uma pergunta do perfil (PromptRepliesController): o balão mostra a pergunta e
  # a resposta citadas. Cópia do texto: editar a pergunta depois não muda a conversa.
  def prompt_reply?
    has_attribute?(:prompt_key) && prompt_key.present?
  end

  def prompt_preview
    return nil unless prompt_reply?

    { key: prompt_key, question: prompt_question, answer: prompt_answer }
  end

  # Resumo da mensagem citada, no formato que o chat_logic.js desenha.
  def reply_to_preview
    return nil unless reply_to

    {
      id:          reply_to.id,
      sender_id:   reply_to.sender_id,
      sender_name: reply_to.sender&.display_name || "Usuário",
      content:     reply_to.content.to_s.truncate(REPLY_PREVIEW_LENGTH)
    }
  end

  # --- Mimos na conversa ---------------------------------------------------------

  def mimo_linked?
    has_attribute?(:mimo_transaction_id) && mimo_transaction_id.present? && mimo_transaction.present?
  end

  # O balão do mimo: mensagem de quem enviou o mimo
  def mimo_gift?
    mimo_linked? && sender_id == mimo_transaction.sender_id
  end

  # O agradecimento: mensagem de quem recebeu, citando o mimo
  def mimo_thanks?
    mimo_linked? && sender_id == mimo_transaction.receiver_id
  end

  def kind
    mimo_gift? ? "mimo" : super
  end

  # O que o balão precisa (o mesmo nos dois lados; quem vê decide "Você enviou" ou
  # "Você recebeu" pelo remetente). url: a tela do mimo — só abre para quem recebeu.
  def mimo_preview
    return nil unless mimo_linked?

    mimo = mimo_transaction
    {
      role:    mimo_gift? ? "gift" : "thanks",
      label:   mimo.display_label,
      icon:    mimo.display_icon,
      price:   Money.new(mimo.price_cents, "BRL").format,
      message: mimo_gift? ? mimo.message.presence : nil,
      url:     Rails.application.routes.url_helpers.mimo_celebration_page_path(mimo.id)
    }
  end

  # A mensagem no formato que o chat_logic.js desenha (broadcast e resposta do envio)
  def chat_payload
    {
      id:         id,
      match_id:   match_id,
      content:    content,
      kind:       kind,
      sender_id:  sender_id,
      status:     status,
      created_at: created_at.iso8601,
      user_name:  sender.display_name || "Usuário",
      avatar_url: sender.avatar_url || "/assets/avatarfoto.jpg",
      verified:   sender.verified?,
      reply_to:   reply_to_preview,
      prompt:     prompt_preview,
      audio:      audio_preview,
      photo:      photo_preview,
      mimo:       mimo_preview
    }
  end

  private

  # A citação só pode apontar para uma mensagem desta conversa: um reply_to_id
  # forjado vazaria, no broadcast, o conteúdo de uma conversa de outras pessoas.
  def reply_to_must_belong_to_same_match
    return if reply_to_id.blank?
    return if reply_to && reply_to.match_id == match_id

    errors.add(:reply_to, "precisa ser uma mensagem desta conversa")
  end

  def broadcast_message
    MatchChannel.broadcast_to(match, { message: chat_payload })
  rescue => e
    Rails.logger.error "[Message#broadcast_message] Falha no broadcast match=#{match_id} error=#{e.class}: #{e.message}"
  end

  def broadcast_edit
    MatchChannel.broadcast_to(match, {
      edited_message: { id: id, content: content, edited_at: edited_at.iso8601 }
    })
  rescue => e
    Rails.logger.error "[Message#broadcast_edit] Falha no broadcast match=#{match_id} error=#{e.class}: #{e.message}"
  end

  def broadcast_deletion
    MatchChannel.broadcast_to(match, { deleted_message_id: id })
  rescue => e
    Rails.logger.error "[Message#broadcast_deletion] Falha no broadcast match=#{match_id} error=#{e.class}: #{e.message}"
  end

  def send_push_notification
    Rails.logger.info "[Message] Enfileirando PushNotificationJob para message=#{id} match=#{match_id}"
    PushNotificationJob.perform_later(id)
  rescue => e
    Rails.logger.error "[Message#send_push_notification] Falha ao enfileirar job message=#{id} error=#{e.class}: #{e.message}"
  end
end
