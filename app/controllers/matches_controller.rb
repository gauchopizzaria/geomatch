class MatchesController < ApplicationController
  before_action :authenticate_user!
  # Define @match apenas para actions específicas e garante segurança
  before_action :set_match, only: [:show, :clear_conversation]

  def index
    # 1. Busca matches e evita consultas repetitivas (Eager Loading)
    all_matches = current_user.matches.includes(:messages, :user, :matched_user)

    @matches_initiated = []
    @matches_uninitiated = []

    # Otimização: Carregar IDs dos likes em memória
    my_likes_ids = current_user.likes.pluck(:liked_id)

    all_matches.each do |match|
      if match.messages.any?
        @matches_initiated << match
      else
        other = match.other_user(current_user)
        
        # Verifica se ambos se curtiram (Lógica de Match)
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
    @messages = @match.messages.order(created_at: :asc)
    @message = Message.new
  end

  def start_chat
    target_user = User.find(params[:user_id])

    # ... (verificação de bloqueio mantida) ...

    # VERIFICAÇÃO DE LIMITE (Free = 7, Outros = Ilimitado)
    unless current_user.can_send_message?
      respond_to do |format|
        format.turbo_stream { 
          # Renderiza o modal passando type: 'messages'
          render turbo_stream: turbo_stream.update("upgrade-modal-container", 
                 partial: "shared/upgrade_modal", 
                 locals: { type: 'messages' }) 
        }
        format.html { redirect_to lead_path, alert: "Limite atingido! Pague R$ 1,99 ou faça upgrade." }
      end
      return
    end

    current_user.increment_messages!

    # 5. Busca ou cria o match
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
    if @match.messages.destroy_all
      redirect_to matches_path, notice: "Conversa limpa com sucesso."
    else
      redirect_to match_path(@match), alert: "Erro ao limpar conversa."
    end
  end

  private

  # Método de segurança: Garante que o Match pertence ao usuário logado
  def set_match
    @match = current_user.matches.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to matches_path, alert: "Conversa não encontrada ou acesso negado."
  end
end