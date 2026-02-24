class MatchesController < ApplicationController
  before_action :authenticate_user!
  # Define @match apenas para actions específicas e garante segurança
  before_action :set_match, only: [:show, :clear_conversation]

  def index
  # 1. Busca matches iniciados ordenados pela data da última mensagem
  # Usamos a função de agregação MAX diretamente no ORDER BY para evitar o erro de coluna inexistente no Postgres
  @matches_initiated = current_user.matches
    .joins(:messages)
    .select('matches.*, MAX(messages.created_at) AS last_msg_at')
    .group('matches.id')
    .order('MAX(messages.created_at) DESC') # Repetimos a função aqui para o Postgres aceitar
    .includes(:user, :matched_user)

  # 2. Pega os IDs para não duplicar na lista de baixo
  initiated_ids = @matches_initiated.pluck(:id)

  # 3. Matches não iniciados (mantendo sua lógica original de verificação de likes)
  @all_uninitiated = current_user.matches
    .where.not(id: initiated_ids)
    .includes(:user, :matched_user)

  @matches_uninitiated = @all_uninitiated.select do |match|
    other = match.other_user(current_user)
    # Sua lógica de segurança de likes
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