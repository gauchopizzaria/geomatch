class MatchesController < ApplicationController
  before_action :authenticate_user!
  # Define @match apenas para actions específicas e garante segurança
  before_action :set_match, only: [:show, :clear_conversation]

  def index
    # 1. IDs dos matches que já têm mensagem, ordenados pela mensagem mais recente.
    # Query separada (apenas em messages) evita o conflito GROUP BY x SELECT *
    # que quebrava no Postgres em produção quando o Rails fazia eager_load do includes.
    initiated_ids_ordered = Message
      .joins(:match)
      .where("matches.user_id = :uid OR matches.matched_user_id = :uid", uid: current_user.id)
      .group(:match_id)
      .order(Arel.sql("MAX(messages.created_at) DESC"))
      .pluck(:match_id)

    # 2. Carrega os matches preservando a ordem dos IDs acima
    @matches_initiated =
      if initiated_ids_ordered.any?
        loaded = Match
          .where(id: initiated_ids_ordered)
          .includes(:user, :matched_user)
          .index_by(&:id)
        initiated_ids_ordered.map { |id| loaded[id] }.compact
      else
        []
      end

    # 3. Matches não iniciados (sem mensagens) — verifica match mútuo via likes
    @all_uninitiated = current_user.matches
      .where.not(id: initiated_ids_ordered)
      .includes(:user, :matched_user)

    @matches_uninitiated = @all_uninitiated.select do |match|
      other = match.other_user(current_user)
      next false if other.nil?
      Like.exists?(liker_id: current_user.id, liked_id: other.id) &&
        Like.exists?(liker_id: other.id, liked_id: current_user.id)
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
    respond_to do |format|
      # Se for um acesso normal (fallback)
      format.html { redirect_to match_path(@match), notice: "Conversa limpa." }
      # Se for via AJAX (o que o seu JS vai usar)
      format.json { head :no_content } 
    end
  else
    respond_to do |format|
      format.html { redirect_to match_path(@match), alert: "Erro ao limpar." }
      format.json { render json: { error: "Erro" }, status: :unprocessable_entity }
    end
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