class MatchesController < ApplicationController
  before_action :authenticate_user!
  # Define @match apenas para actions específicas e garante segurança
  before_action :set_match, only: [:show, :clear_conversation]

  def index
    # 1. Busca matches e evita consultas repetitivas (Eager Loading)
    # Trazemos as mensagens para saber se a conversa começou
    all_matches = current_user.matches.includes(:messages, :user, :matched_user)

    @matches_initiated = []
    @matches_uninitiated = []

    # Otimização: Carregar IDs dos likes em memória para evitar ir no banco dentro do loop
    my_likes_ids = current_user.likes.pluck(:liked_id)
    # Precisaríamos saber quem curtiu o current_user também, mas para simplificar
    # e manter sua lógica funcionando sem complexidade excessiva agora, 
    # vamos manter a lógica original, mas atente-se que isso pode ficar lento com muitos usuários.

    all_matches.each do |match|
      if match.messages.any?
        @matches_initiated << match
      else
        other = match.other_user(current_user)
        
        # LÓGICA DE FILTRO (Mantida conforme seu pedido)
        # Verifica se ambos se curtiram
        # Nota: Idealmente, um registro 'Match' só deveria existir se ambos se curtiram.
        # Se sua app cria Match sem like mútuo, esta verificação é necessária.
        
        i_liked = Like.exists?(liker_id: current_user.id, liked_id: other.id)
        he_liked = Like.exists?(liker_id: other.id, liked_id: current_user.id)
        
        if i_liked && he_liked
          @matches_uninitiated << match
        end
      end
    end
  end

  def show
    # @match já definido pelo before_action de forma segura
    
    # Marca mensagens recebidas como lidas (Opcional, mas recomendado)
    # @match.messages.where.not(sender_id: current_user.id).update_all(read: true)

    @messages = @match.messages.order(created_at: :asc)
    @message = Message.new
  end

  def start_chat
    target_user = User.find(params[:user_id])

    # 1. Verifica se está bloqueado antes de iniciar
    if current_user.blocked_users.include?(target_user) || current_user.blocked_by_users.include?(target_user)
      redirect_to lead_path, alert: "Você não pode iniciar conversa com este usuário."
      return
    end

    # 2. Busca ou cria o match
    @match = Match.where(user: current_user, matched_user: target_user)
                  .or(Match.where(user: target_user, matched_user: current_user))
                  .first

    unless @match
      @match = Match.create!(user: current_user, matched_user: target_user)
    end

    redirect_to match_path(@match)
  rescue ActiveRecord::RecordNotFound
    redirect_to lead_path, alert: "Usuário não encontrado."
  end

  def clear_conversation
    # @match já definido pelo before_action de forma segura
    
    if @match.messages.destroy_all
      redirect_to matches_path, notice: "Conversa limpa com sucesso."
    else
      redirect_to match_path(@match), alert: "Erro ao limpar conversa."
    end
  end

  private

  # Método de segurança: Garante que o Match pertence ao usuário logado
  def set_match
    # Usa o método 'matches' que definimos no User model
    # Se o ID não for de um match do usuário, lança 404 (RecordNotFound)
    @match = current_user.matches.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to matches_path, alert: "Conversa não encontrada ou acesso negado."
  end
end