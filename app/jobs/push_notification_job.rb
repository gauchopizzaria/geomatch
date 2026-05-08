class PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    recipient = message.match.other_user(message.sender)
    return unless recipient
    return if recipient.id == message.sender_id

    unless ENV["VAPID_PUBLIC_KEY"].present? && ENV["VAPID_PRIVATE_KEY"].present?
      Rails.logger.error "[PushNotificationJob] VAPID keys not configured — skipping message=#{message_id}"
      return
    end

    vapid = {
      subject:     ENV.fetch("VAPID_SUBJECT", "mailto:contato@geomatch.app"),
      public_key:  ENV["VAPID_PUBLIC_KEY"],
      private_key: ENV["VAPID_PRIVATE_KEY"]
    }

    title = message.sender.display_name
    body  = message.content.truncate(80)
    url   = "/matches/#{message.match_id}"

    payload = {
      title: title,
      body:  body,
      data:  { path: url, app: "GeoMatch" },
      tag:   "chat-#{message.match_id}"
    }.to_json

    recipient.push_subscriptions.each do |subscription|
      ::WebPush.payload_send(
        message:      payload,
        endpoint:     subscription.endpoint,
        p256dh:       subscription.p256dh,
        auth:         subscription.auth,
        vapid:        vapid,
        ssl_timeout:  5,
        open_timeout: 5,
        read_timeout: 5
      )
    rescue ::WebPush::ExpiredSubscription
      subscription.destroy
    rescue => e
      Rails.logger.error "[PushNotificationJob] message=#{message_id} subscription=#{subscription.id} error=#{e.message}"
    end

    # NOVO Disparo (iOS Push via APNs)
    if recipient.apns_token.present?
      begin
        connection = Apnotic::Connection.new(
          cert_path: Rails.root.join("config/apns.p8"),
          key_id: ENV["APNS_KEY_ID"],
          team_id: ENV["APNS_TEAM_ID"]
        )

        notification = Apnotic::Notification.new(recipient.apns_token)
        notification.alert = { title: title, body: body }
        notification.custom_payload = { url: url }
        notification.topic = "br.com.geomatch.app"

        connection.push(notification)
      rescue => e
        Rails.logger.error "[PushNotificationJob] message=#{message_id} apns error=#{e.message}"
      ensure
        connection&.close
      end
    end
  end
end
