class Users::SessionsController < Devise::SessionsController
  def destroy
    # Broadcast explícito de "leave" antes de destruir a sessão, garantindo que
    # o marcador do usuário desapareça imediatamente do mapa de todos ao fazer logout.
    # (O MapChannel#unsubscribed faria isso, mas pode ter um delay de reconexão do AC.)
    if current_user
      ActionCable.server.broadcast("map_updates", {
        action:  "leave",
        user_id: current_user.id
      })
    end
    super
  end
end
