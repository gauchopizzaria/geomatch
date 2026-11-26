json.match_id @match.id

json.messages @messages do |message|
  json.id         message.id
  json.content    message.content
  json.sent_at    message.created_at.iso8601
  json.read_at    message.read_at&.iso8601
  json.is_mine    message.sender_id == current_api_user.id
  json.reply_to_id message.reply_to_id

  # "text", "audio" (mensagem de voz), "photo" ou "mimo" (o balão do mimo) — nesses
  # três o content é só o rótulo
  json.kind message.kind
  # Mimo: o balão do mimo (role "gift") ou o agradecimento que cita o mimo ("thanks")
  json.mimo message.mimo_preview if Message.mimo_messages? && message.mimo_linked?
  if message.audio?
    json.audio do
      json.url      rails_blob_url(message.audio)
      json.duration message.audio_duration
      json.peaks    message.audio_peaks
    end
  elsif message.photo?
    json.photo do
      json.url    rails_blob_url(message.photo)
      json.width  message.photo.blob.metadata["gm_width"].to_i
      json.height message.photo.blob.metadata["gm_height"].to_i
    end
  end

  json.sender do
    json.id         message.sender.id
    json.name       message.sender.display_name
    json.avatar_url message.sender.avatar_url
  end

  json.reactions message.reactions.group_by(&:emoji).transform_values(&:count)
end
