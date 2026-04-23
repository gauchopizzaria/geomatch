class PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    recipient = message.match.other_user(message.sender)
    return unless recipient
    return if recipient.id == message.sender_id

    vapid = {
      subject:     ENV.fetch("APP_BASE_URL", "mailto:contato@geomatch.app"),
      public_key:  ENV["VAPID_PUBLIC_KEY"],
      private_key: ENV["VAPID_PRIVATE_KEY"]
    }

    payload = {
      title: message.sender.display_name,
      body:  message.content.truncate(80),
      data:  { path: "/matches/#{message.match_id}", app: "GeoMatch" },
      tag:   "chat-#{message.match_id}"
    }.to_json

    recipient.push_subscriptions.each do |subscription|
      WebPush.payload_send(
        message:  payload,
        endpoint: subscription.endpoint,
        p256dh:   subscription.p256dh,
        auth:     subscription.auth,
        vapid:    vapid
      )
    rescue WebPush::ExpiredSubscription
      subscription.destroy
    rescue => e
      Rails.logger.error "[PushNotificationJob] message=#{message_id} subscription=#{subscription.id} error=#{e.message}"
    end
  end
end
