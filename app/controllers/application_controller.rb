class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :disable_cache_for_auth, if: :devise_controller?
  before_action :update_last_seen, if: :user_signed_in?

  rescue_from ActionController::InvalidAuthenticityToken, with: :redirect_and_refresh_token

  protected

  def configure_permitted_parameters
    # Adicionei :terms_of_use e :data_policy na lista de atributos permitidos
    attributes = [
      :username, :bio, :birthdate, :avatar, :gender, :phone, :address,
      :terms_of_use, :data_policy,
      :education_level, :zip_code, :street, :neighborhood, :city, :state
    ]

    devise_parameter_sanitizer.permit(:sign_up, keys: attributes)
    devise_parameter_sanitizer.permit(:account_update, keys: attributes + [:share_location])
  end

  # Atualiza o "visto por último" do usuário logado
  def update_last_seen
    # update_column -> rápido, sem validações, sem callbacks
    current_user.update_column(:last_seen_at, Time.current)
  end

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

    # Redireciona para /discover_3d após o login
  def after_sign_in_path_for(resource)
    discover_3d_path
  end

  private

  def disable_cache_for_auth
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"]        = "no-cache"
    response.headers["Expires"]       = "Fri, 01 Jan 1990 00:00:00 GMT"
  end

  def redirect_and_refresh_token
    redirect_to new_user_session_path, alert: "Sessão atualizada por segurança. Por favor, tente novamente."
  end
end