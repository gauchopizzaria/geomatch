module ApplicationHelper
  def turbo_native_app?
    request.user_agent.to_s.include?('Turbo Native')
  end

  def render_turbo_stream_flash_messages
    turbo_stream.prepend 'toast-container', partial: 'shared/flash'
  end
end
