# app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  before_action :authenticate_user!

  def index
    # 1. Notificações (Quem te curtiu)
    @notifications = current_user.notifications.order(created_at: :desc)

    # 2. Quem VOCÊ curtiu
    # CORREÇÃO AQUI: Trocamos 'user_id' por 'liker_id' conforme o erro do banco
    @my_likes = Like.where(liker_id: current_user.id).order(created_at: :desc)

    # Marca todas como lidas ao visitar a página
    current_user.notifications.unread.update_all(read_at: Time.current)
  end
end