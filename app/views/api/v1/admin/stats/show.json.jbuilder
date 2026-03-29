json.generated_at Time.current.iso8601

json.users do
  json.total        @stats[:total_users]
  json.active_now   @stats[:active_now]
  json.new_today    @stats[:new_today]
  json.banned       @stats[:banned_users]
end

json.engagement do
  json.total_matches   @stats[:total_matches]
  json.messages_today  @stats[:messages_today]
end

json.moderation do
  json.pending_reports @stats[:pending_reports]
end
