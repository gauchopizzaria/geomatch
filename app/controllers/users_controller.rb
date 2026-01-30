class UsersController < ApplicationController
  before_action :authenticate_user!
  
  # Ação de Bloqueio deve ser PÚBLICA (antes do private)
  def block
    @user_to_block = User.find(params[:id])
    
    # 1. Cria o bloqueio no banco
    # O 'blocks_sent' foi definido no User model no passo anterior
    current_user.blocks_sent.create!(blocked: @user_to_block)
    
    # 2. Destrói qualquer Match existente entre os dois
    # CORREÇÃO: Usamos a sintaxe de hash correta baseada no model Match (user e matched_user)
    Match.where(user: current_user, matched_user: @user_to_block)
         .or(Match.where(user: @user_to_block, matched_user: current_user))
         .destroy_all

    # 3. (Opcional) Destruir Likes para limpar vestígios
    Like.where(liker: current_user, liked: @user_to_block).destroy_all
    Like.where(liker: @user_to_block, liked: current_user).destroy_all

    redirect_to matches_path, notice: "Usuário bloqueado com sucesso."
  rescue ActiveRecord::RecordInvalid
    redirect_to matches_path, alert: "Erro ao bloquear usuário."
  end

  # ==========================================
  #  OUTRAS ACTIONS
  # ==========================================

  def discover
    # A busca inicial será feita via JS
  end

  def show
    @user = User.find(params[:id])

    # SEGURANÇA: Impedir que usuário veja perfil de quem o bloqueou (ou quem ele bloqueou)
    # Usamos o helper 'excluded_user_ids' que criamos no Model User
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
  def report_incident; end

  def preview
    @user = current_user
  end

  # ==========================================
  #  ACTION LEAD
  # ==========================================
  def lead
    # 1. POPUP DE MATCH
    if params[:match] == "true" && params[:match_id].present?
      @match = Match.find(params[:match_id])
      # Garante que só os participantes vejam o match
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
    # Passamos os IDs de quem JÁ curtimos E quem BLOQUEAMOS/NOS BLOQUEARAM para ignorar
    ignored_ids = current_user.likes.pluck(:liked_id) + current_user.excluded_user_ids
    
    @next_user, @distance = AdvancedDiscoveryService.new(current_user)
                                          .find_next_eligible_user(ignored_ids, filters)
  end

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

    # FILTRO DE SEGURANÇA: Remover usuários bloqueados da lista do mapa
    blocked_ids = current_user.excluded_user_ids
    users = users.reject { |u| blocked_ids.include?(u.id) }

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
      redirect_to edit_profile_path, notice: "Perfil atualizado!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def reject
    # LÓGICA IMPORTANTE FALTANDO:
    # Você precisa salvar que rejeitou este usuário, senão ele aparece de novo.
    # Sugestão: Criar um Like com like_type: 'pass' ou um model Reject.
    # Exemplo simples usando Like com boolean false (se sua lógica permitir):
    # current_user.likes.create(liked_id: params[:user_id], liked: false) 
    
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
      :share_location, :interested_in,
      { hobbies_list: [] },
      album_photos: []
    )
  end
  # Fim da classe
end