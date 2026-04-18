module ApplicationHelper
  def turbo_native_app?
    request.user_agent.to_s.include?('Turbo Native')
  end
end
