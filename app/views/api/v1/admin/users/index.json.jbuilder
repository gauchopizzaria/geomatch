json.pagination do
  json.current_page @users.current_page
  json.total_pages  @users.total_pages
  json.total_count  @users.total_count
  json.per_page     @users.limit_value
end

json.users @users do |user|
  json.id           user.id
  json.name         user.display_name
  json.email        user.email
  json.plan         user.plan&.name
  json.city         user.city
  json.state        user.state
  json.admin        user.admin?
  json.verified     user.verified?
  json.banned       user.banned?
  json.banned_at    user.banned_at&.iso8601
  json.created_at   user.created_at.iso8601
  json.last_seen_at user.last_seen_at&.iso8601
  json.status       user.banned? ? 'banned' : 'active'
end
