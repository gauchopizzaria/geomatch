class LikesController < ApplicationController
  before_action :authenticate_user!

  def create
    liked_user = User.find(params[:user_id])

    # Evitar duplicações
    if Like.exists?(liker_id: current_user.id, liked_id: liked_user.id)
      return redirect_to lead_path, alert: "Você já curtiu este usuário."
    end

    @like = Like.new(liker_id: current_user.id, liked_id: liked_user.id)

    if @like.save

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

        redirect_to lead_path(match: true, match_id: match.id)

      else
        # 🔔 Notificação de LIKE RECEBIDO
        notification = Notification.create(
          recipient: liked_user,
          actor: current_user,
          action: "curtiu seu perfil",
          notifiable: @like
        )

        NotificationBroadcastJob.perform_later(notification)

        redirect_to lead_path, notice: "Curtida enviada!"
      end

    else
      redirect_to lead_path, alert: "Não foi possível registrar a curtida."
    end

  rescue => e
    Rails.logger.error("Erro ao curtir: #{e.message}")
    redirect_to lead_path, alert: "Erro interno no servidor."
  end
end
