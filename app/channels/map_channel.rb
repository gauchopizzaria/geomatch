class MapChannel < ApplicationCable::Channel
  def subscribed
    stream_from "map_updates"
  end

  def unsubscribed
    ActionCable.server.broadcast("map_updates", {
      action:  "leave",
      user_id: current_user.id
    })
  end
end
