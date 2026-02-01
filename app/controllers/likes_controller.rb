class LikesController < ApplicationController
  before_action :authenticate_user!

  def create
    liked_user = User.find(params[:user_id])

    # 1. VERIFICAÇÃO DE LIMITE
    unless current_user.can_like?
      respond_to do |format|
        # --- MUDANÇA AQUI: Usa 'update' no container específico ---
        format.turbo_stream { 
          render turbo_stream: turbo_stream.update("upgrade-modal-container", partial: "shared/upgrade_modal", locals: { type: 'likes' }) 
        }
        format.html { redirect_to lead_path, alert: "Você atingiu seu limite de curtidas diárias." }
      end
      return
    end
    # =======================================================

    # Evitar duplicações
    if Like.exists?(liker_id: current_user.id, liked_id: liked_user.id)
      # Se veio do MAPA, apenas fecha o popup (ok)
      if params[:source] == "map"
        return head :ok 
      else
        return redirect_to lead_path, alert: "Você já curtiu este usuário."
      end
    end

    @like = Like.new(liker_id: current_user.id, liked_id: liked_user.id)

    if @like.save
      
      # =====================================================
      # 2. INCREMENTA O CONTADOR (NOVO)
      # =====================================================
      current_user.increment_likes!
      # =====================================================

      # Se o outro usuário já curtiu você → MATCH
      if Like.exists?(liker_id: liked_user.id, liked_id: current_user.id)

        existing_match = Match.where(
          "(user_id = ? AND matched_user_id = ?) OR (user_id = ? AND matched_user_id = ?)",
          current_user.id, liked_user.id,
          liked_user.id, current_user.id 
        ).first

        match = existing_match
        unless existing_match
          user_id = [current_user.id, liked_user.id].min
          matched_user_id = [current_user.id, liked_user.id].max
          match = Match.create(user_id: user_id, matched_user_id: matched_user_id, status: "matched")
        end

        # 🔔 Notificação de MATCH
        notification = Notification.create(
          recipient: liked_user,
          actor: current_user,
          action: "vocês deram match!",
          notifiable: match
        )

        NotificationBroadcastJob.perform_later(notification)

        # --- LÓGICA DE RETORNO DO MATCH ---
        if params[:source] == "map"
          # Se veio do mapa e deu Match, redireciona para a conversa
          redirect_to match_path(match)
        else
          # Se veio do swipe, mostra o popup de match
          redirect_to lead_path(match: true, match_id: match.id)
        end

      else
        # 🔔 Notificação de LIKE RECEBIDO
        notification = Notification.create(
          recipient: liked_user,
          actor: current_user,
          action: "curtiu seu perfil",
          notifiable: @like
        )

        NotificationBroadcastJob.perform_later(notification)

        # --- LÓGICA DE RETORNO DO LIKE SIMPLES ---
        if params[:source] == "map"
          # Se veio do mapa, apenas diz OK (para o JS fechar o popup)
          head :ok
        else
          # Se veio do swipe, recarrega a página para o próximo card
          redirect_to lead_path, notice: "Curtida enviada!"
        end
      end

    else
      # Erro ao salvar
      if params[:source] == "map"
        head :unprocessable_entity
      else
        redirect_to lead_path, alert: "Não foi possível registrar a curtida."
      end
    end

  rescue => e
    Rails.logger.error("Erro ao curtir: #{e.message}")
    if params[:source] == "map"
      head :internal_server_error
    else
      redirect_to lead_path, alert: "Erro interno no servidor."
    end
  end
end