class UsersController < ApplicationController
  before_action :authenticate_user!

  # Página do mapa
  def discover
    # A busca inicial será feita via JS
  end

  # Perfil Público
  def show
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to discover_path, alert: "Usuário não encontrado."
  end

  def me_profile
    @user = current_user
  end

  def safety_center; end
  def report_incident; end

  def preview
    @user = current_user
  end

  # ==========================================
  #  ACTION LEAD (CORRIGIDA)
  # ==========================================
  def lead
    # 🚨 1. CASO SEJA POPUP DE MATCH
    if params[:match] == "true" && params[:match_id].present?
      @match = Match.find(params[:match_id])
      @next_user = @match.user_id == current_user.id ? @match.matched_user : @match.user
      return # Para aqui e exibe o popup
    end

    # 🔍 2. PREPARA OS FILTROS (Lógica Nova)
    filters = {
      distance: params[:distance].presence || 500, # Padrão 500km
      min_age:  params[:min_age].presence || 18,
      max_age:  params[:max_age].presence || 60
    }

    # Variáveis para a View (para manter os inputs preenchidos)
    @filter_distance = filters[:distance]
    @filter_min_age  = filters[:min_age]
    @filter_max_age  = filters[:max_age]

    # 🚀 3. BUSCA O PRÓXIMO USUÁRIO
    liked_ids = current_user.likes.pluck(:liked_id)
    
    # Chama o serviço passando os FILTROS
    @next_user, @distance = AdvancedDiscoveryService.new(current_user)
                                                    .find_next_eligible_user(liked_ids, filters)

    # Renderiza a view normalmente
  end
  # ==========================================

  # Endpoint JSON para retornar usuários próximos
  def nearby
    latitude = params[:latitude].to_f
    longitude = params[:longitude].to_f
    range_km = params[:range].to_i.presence || 50 
    gender_filter = params[:gender]&.downcase

    if latitude.present? && longitude.present?
      current_user.update(latitude: latitude, longitude: longitude)
    end

    if latitude.zero? && longitude.zero?
      render json: [], status: :ok
      return
    end

    users = DiscoveryService.new(current_user).find_nearby_users(range_km, gender_filter)

    render json: users.as_json(only: [:id, :username, :latitude, :longitude, :avatar_url, :distance_km, :city])
  rescue => e
    Rails.logger.error "Erro em /users/nearby: #{e.message}"
    render json: { error: "Erro interno" }, status: :internal_server_error
  end

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    if params[:user][:album_photos].present?
      @user.album_photos.attach(params[:user][:album_photos])
    end

    user_update_params = user_params.except(:album_photos)

    if @user.update(user_update_params)
      redirect_to edit_profile_path, notice: "Perfil atualizado com sucesso!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def reject
    rejected_user = User.find(params[:user_id])
    redirect_to lead_path
  rescue ActiveRecord::RecordNotFound
    redirect_to lead_path, alert: "Usuário não encontrado."
  end

  private

  def user_params
    params.require(:user).permit(
      :avatar, :username, :bio, :birthdate, :gender,
      :share_location, :interested_in,
      { hobbies_list: [] },
      album_photos: []
    )
  end
end