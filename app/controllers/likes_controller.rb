class LikesController < ApplicationController
  before_action :authenticate_user!

  def create
    liked_user = User.find(params[:user_id])

    # 1. Verifica se o like já existe para evitar erro de duplicidade
    if Like.exists?(liker_id: current_user.id, liked_id: liked_user.id)
      return redirect_to lead_path, alert: "Você já curtiu este usuário."
    end

    @like = Like.new(
      liker_id: current_user.id,
      liked_id: liked_user.id
    )

 if @like.save
      if Like.exists?(liker_id: liked_user.id, liked_id: current_user.id)
        # Lógica de Match
        # Verifica se o match já existe para evitar duplicatas
        existing_match = Match.where(
          "(user_id = ? AND matched_user_id = ?) OR (user_id = ? AND matched_user_id = ?)",
          current_user.id, liked_user.id,
          liked_user.id, current_user.id 
        ).first
        
        match = existing_match # Inicializa com o existente, se houver

        unless existing_match
          # Cria apenas um match com o usuário de menor ID como user_id (para garantir unicidade)
          user_id = [current_user.id, liked_user.id].min
          matched_user_id = [current_user.id, liked_user.id].max
          match = Match.create(user_id: user_id, matched_user_id: matched_user_id, status: "matched")
        end
        
        # Redireciona para a próxima pessoa após o match
        redirect_to lead_path, notice: "💘 Deu match!"
      else
          # Lógica de Notificação de Like Recebido
      Notification.create(
        recipient: liked_user,
        actor: current_user,
        action: "curtiu seu perfil",
        notifiable: @like
      )
       
       NotificationBroadcastJob.perform_later(notification)

        # Redireciona para a próxima pessoa após a curtida
        redirect_to lead_path, notice: "Curtida enviada!"
      end
    else
      # 2. Se o save falhar por outro motivo (ex: validação), retorna erro genérico
      redirect_to lead_path, alert: "Não foi possível registrar a curtida. Tente novamente."
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to lead_path, alert: "Usuário não encontrado."
  rescue => e
    Rails.logger.error("Erro ao curtir: #{e.message}")
    redirect_to lead_path, alert: "Erro interno no servidor."
  end
end
