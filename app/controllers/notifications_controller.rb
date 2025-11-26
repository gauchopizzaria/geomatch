# app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @notifications = current_user.notifications.order(created_at: :desc)
    # Marca todas como lidas ao visitar a página
    current_user.notifications.unread.update_all(read_at: Time.current)
  end
end
