class LikesController < ApplicationController
  before_action :authenticate_user!

  def create
    liked_user = User.find(params[:user_id])

    # 1. Verifica se o like já existe para evitar erro de duplicidade
    if Like.exists?(liker_id: current_user.id, liked_id: liked_user.id)
      return render json: { message: "Você já curtiu este usuário.", status: "already_liked" }, status: :ok
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
        
        # Retorna o match_id na resposta JSON para o frontend
        render json: { message: "💘 Deu match!", match_id: match.id }, status: :ok
      else
          # Lógica de Notificação de Like Recebido
      Notification.create(
        recipient: liked_user,
        actor: current_user,
        action: "curtiu seu perfil",
        notifiable: @like
      )
       
       NotificationBroadcastJob.perform_later(notification)

        # Lógica de Notificação de Like Recebido (Veja o Passo 3)
        render json: { message: "Curtida enviada!" }, status: :ok
      end
    else
      # 2. Se o save falhar por outro motivo (ex: validação), retorna erro genérico
      render json: { error: "Não foi possível registrar a curtida. Tente novamente." }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Usuário não encontrado" }, status: :not_found
  rescue => e
    Rails.logger.error("Erro ao curtir: #{e.message}")
    render json: { error: "Erro interno no servidor" }, status: :internal_server_error
  end
end
