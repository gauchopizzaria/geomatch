require "stringio"

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
      connection = nil
      begin
        raw_env = ENV.fetch("APNS_KEY_P8", "")

        # Remove os cabeçalhos e TODOS os espaços, tabs ou quebras de linha
        pure_base64 = raw_env.gsub(/-----BEGIN PRIVATE KEY-----/, "")
                             .gsub(/-----END PRIVATE KEY-----/, "")
                             .gsub(/\s+/, "")

        # Reconstrói o formato PEM estrito exigido pelo OpenSSL (linhas de 64 caracteres)
        formatted_key = "-----BEGIN PRIVATE KEY-----\n#{pure_base64.scan(/.{1,64}/).join("\n")}\n-----END PRIVATE KEY-----\n"

        p8_key = StringIO.new(formatted_key)

        connection_options = {
          auth_method: :token,
          cert_path:   p8_key,
          key_id:      ENV.fetch("APNS_KEY_ID"),
          team_id:     ENV.fetch("APNS_TEAM_ID")
        }

        connection = if ENV.fetch("APNS_ENV", "production") == "development"
                       Apnotic::Connection.development(connection_options)
                     else
                       Apnotic::Connection.new(connection_options)
                     end

        notification = Apnotic::Notification.new(recipient.apns_token)
        notification.alert = { title: title, body: body }
        notification.custom_payload = { url: url }
        notification.topic = ENV.fetch("APNS_TOPIC", "br.com.geomatch.app")

        response = connection.push(notification)

        if response&.ok?
          Rails.logger.info "[PushNotificationJob] message=#{message_id} apns ok recipient=#{recipient.id}"
        else
          Rails.logger.error "[PushNotificationJob] message=#{message_id} apns failed status=#{response&.status} body=#{response&.body}"
        end
      rescue => e
        Rails.logger.error "[PushNotificationJob] message=#{message_id} apns error=#{e.class}: #{e.message}"
      ensure
        connection&.close
      end
    end
  end
end
