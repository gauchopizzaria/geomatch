class UsersController < ApplicationController
  before_action :authenticate_user!
  
  # ==========================================
  #  AÇÕES DE SEGURANÇA E INTERAÇÃO
  # ==========================================

  # Ação para bloquear usuário (Via POST)
  def block
    @user_to_block = User.find(params[:id])
    
    # 1. Cria o bloqueio no banco
    current_user.blocks_sent.create!(blocked: @user_to_block)
    
    # 2. Destrói qualquer Match e Chat existente
    Match.where(user: current_user, matched_user: @user_to_block)
         .or(Match.where(user: @user_to_block, matched_user: current_user))
         .destroy_all

    # 3. Limpa Likes
    Like.where(liker: current_user, liked: @user_to_block).destroy_all
    Like.where(liker: @user_to_block, liked: current_user).destroy_all

    # Redireciona de volta para o Lead (Discovery) para continuar vendo outros perfis
    redirect_to lead_path, notice: "Usuário bloqueado. Você não verá mais este perfil."
  rescue ActiveRecord::RecordInvalid
    redirect_to lead_path, alert: "Erro ao bloquear usuário."
  end

  # Ação para o botão de "Modo Invisível" no Mapa
  def toggle_visibility
    # Inverte o status atual (true -> false / false -> true)
    # Requer coluna 'invisible' na tabela users (migration já feita?)
    new_status = !current_user.invisible
    
    if current_user.update(invisible: new_status)
      render json: { invisible: new_status, message: "Visibilidade alterada" }, status: :ok
    else
      render json: { error: "Erro ao atualizar" }, status: :unprocessable_entity
    end
  end

  # Ação para atualizar localização (chamada via JS as vezes)
  def update_location
    if params[:latitude].present? && params[:longitude].present?
      current_user.update(latitude: params[:latitude], longitude: params[:longitude])
      head :ok
    else
      head :unprocessable_entity
    end
  end

  # ==========================================
  #  VIEWS PRINCIPAIS
  # ==========================================

  def discover
    # Apenas renderiza a view do mapa. A busca real é feita via AJAX no 'nearby'
  end

  def show
    @user = User.find(params[:id])

    # SEGURANÇA: Verifica bloqueios antes de mostrar o perfil
    if current_user.excluded_user_ids.include?(@user.id)
      redirect_to discover_path, alert: "Perfil indisponível."
      return
    end

  rescue ActiveRecord::RecordNotFound
    redirect_to discover_path, alert: "Usuário não encontrado."
  end

  def me_profile
    @user = current_user
  end

  def safety_center; end

  # Página de Denúncia
  def report_incident
    # Se vier com um ID na URL (clicou em denunciar no perfil), carregamos o usuário
    if params[:user_id].present?
      @reported_user = User.find_by(id: params[:user_id])
    end
  end

  def preview
    @user = current_user
  end

  # ==========================================
  #  ACTION LEAD (SWIPE / TINDER)
  # ==========================================
  def lead
  # 0. GARANTE LOCALIZAÇÃO (fallback DEV)
  if current_user.latitude.nil? || current_user.longitude.nil?
    current_user.update(latitude: -14.7876, longitude: -39.2781)
  end

  # 1. POPUP DE MATCH (Se acabou de dar match)
  if params[:match] == "true" && params[:match_id].present?
    @match = Match.find(params[:match_id])

    if @match.user_id == current_user.id || @match.matched_user_id == current_user.id
      @next_user = @match.other_user(current_user)
      return
    end
  end

    # 2. FILTROS
    filters = {
      distance: params[:distance].presence || 500,
      min_age:  params[:min_age].presence || 18,
      max_age:  params[:max_age].presence || 60
    }

    @filter_distance = filters[:distance]
    @filter_min_age  = filters[:min_age]
    @filter_max_age  = filters[:max_age]

    # 3. BUSCA
    # Ignora: Já curtidos + Bloqueados + Quem me bloqueou
    # pluck(:liked_id) pega tanto likes quanto rejects (ambos estão na tabela likes)
    ignored_ids = current_user.likes.pluck(:liked_id) + current_user.excluded_user_ids
    
    @next_user, @distance = AdvancedDiscoveryService.new(current_user)
                                      .find_next_eligible_user(ignored_ids, filters)
  end

  # ==========================================
  #  API DO MAPA (NEARBY)
  # ==========================================
  def nearby
    latitude = params[:latitude].to_f
    longitude = params[:longitude].to_f
    range_km = params[:range].to_i.presence || 50 
    gender_filter = params[:gender]&.downcase

    # Sempre atualiza a posição do usuário atual para ele saber onde está
    if latitude.present? && longitude.present?
      current_user.update(latitude: latitude, longitude: longitude)
    end

    if latitude.zero? && longitude.zero?
      render json: [], status: :ok
      return
    end

    # Busca usuários próximos usando o Service
    users = DiscoveryService.new(current_user).find_nearby_users(range_km, gender_filter)

    # FILTRAGEM FINAL:
    # 1. Remove bloqueados (excluded_user_ids)
    # 2. Remove quem está INVISÍVEL (invisible: true)
    blocked_ids = current_user.excluded_user_ids
    
    visible_users = users.select do |u| 
      !blocked_ids.include?(u.id) && (u.respond_to?(:invisible) ? !u.invisible : true)
    end

    render json: visible_users.as_json(only: [:id, :username, :latitude, :longitude, :avatar_url, :distance_km, :city])
  rescue => e
    Rails.logger.error "Erro em /users/nearby: #{e.message}"
    render json: { error: "Erro interno" }, status: :internal_server_error
  end

  # ==========================================
  #  EDIÇÃO DE PERFIL
  # ==========================================
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
      redirect_to edit_profile_path, notice: "Perfil atualizado!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # AÇÃO CORRIGIDA
  def reject
    # Cria o registro de 'pass' para não mostrar o usuário novamente
    # IMPORTANTE: Usando 'is_like: false' em vez de 'liked: false'
    current_user.likes.create(liked_id: params[:user_id], is_like: false) 
    
    redirect_to lead_path
  rescue ActiveRecord::RecordNotFound
    redirect_to lead_path
  end

  # ==========================================
  #  PRIVATE
  # ==========================================
  private

  def user_params
    params.require(:user).permit(
      :avatar, :username, :bio, :birthdate, :gender,
      :share_location, :interested_in, :invisible, # Adicionado invisible aos permitidos
      { hobbies_list: [] },
      album_photos: []
    )
  end
end