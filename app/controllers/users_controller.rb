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
    # 1. VERIFICAÇÃO: Só Gold pode usar
    unless current_user.can_use_invisible_mode?
      # Retorna um erro 403 (Proibido) com uma flag para o JS abrir o modal
      return render json: { upgrade_required: true, plan: 'Gold' }, status: :forbidden
    end

    # 2. Executa a troca se for Gold
    new_status = !current_user.invisible
    
    if current_user.update(invisible: new_status)
      render json: { invisible: new_status, message: "Visibilidade alterada" }, status: :ok
    else
      render json: { error: "Erro ao atualizar" }, status: :unprocessable_entity
    end
  end

  # Ação para atualizar localização (chamada via JS as vezes)
  def update_location
    if current_user.invisible
    return head :ok # Retorna sucesso mas não salva nada
    end
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
        # return (Removido return para não quebrar o resto da página se houver match)
        # Idealmente, o modal aparece SOBRE a tela normal. 
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
  #  API DO MAPA (NEARBY) -- CORRIGIDA --
  # ==========================================
  def nearby
    latitude = params[:latitude].to_f
    longitude = params[:longitude].to_f
    range_km = params[:range].to_i.presence || 50 
    gender_filter = params[:gender]&.downcase

    # Sempre atualiza a posição do usuário atual para ele saber onde está
    if latitude.present? && longitude.present? && !current_user.invisible
  current_user.update(latitude: latitude, longitude: longitude)
end

    # Se veio 0.0, 0.0, é bug de GPS, retorna vazio
    if latitude.zero? && longitude.zero?
      render json: [], status: :ok
      return
    end

    # Busca usuários próximos usando o Service
    # ATENÇÃO: Se o Service já devolve JSON (Hash), não podemos chamar .id nele
    users_data = DiscoveryService.new(current_user).find_nearby_users(range_km, gender_filter)

    # FILTRAGEM FINAL SEGURA:
    blocked_ids = current_user.excluded_user_ids
    
    visible_users = users_data.select do |u| 
      # Verifica se 'u' é Objeto (User) ou Hash (JSON)
      uid = u.respond_to?(:id) ? u.id : u[:id] || u['id']
      
      # Verifica invisibilidade (Se for Hash, assume visível ou checa chave)
      is_invisible = if u.respond_to?(:invisible)
                       u.invisible
                     elsif u.is_a?(Hash)
                       u[:invisible] || u['invisible'] || false
                     else
                       false
                     end

      # Regra: Não pode estar bloqueado E não pode estar invisível
      !blocked_ids.include?(uid) && !is_invisible
    end

    # Se for Hash, já está pronto. Se for User, converte.
    final_json = visible_users.map do |u|
      if u.is_a?(Hash)
        u # Já é JSON
      else
        u.as_json(only: [:id, :username, :latitude, :longitude, :distance_km, :city]).merge({
          avatar_url: u.avatar_url # Garante que avatar venha certo
        })
      end
    end

    render json: final_json
  rescue => e
    Rails.logger.error "Erro em /users/nearby: #{e.message}"
    render json: { error: "Erro interno", details: e.message }, status: :internal_server_error
  end

  # ==========================================
  #  EDIÇÃO DE PERFIL
  # ==========================================
  def edit
    @user = current_user
  end

  def update
  @user = current_user

  # 1. Tratamento das fotos do álbum
  if params[:user][:album_photos].present?
    @user.album_photos.attach(params[:user][:album_photos])
  end

  # 2. Removemos album_photos dos parâmetros de atualização em massa
  # para evitar que o Rails tente sobrescrever o que acabamos de anexar
  user_update_params = user_params.except(:album_photos)

  if @user.update(user_update_params)
    # 3. Respondemos de forma amigável ao Turbo/HTML
    respond_to do |format|
      format.html { redirect_to edit_profile_path, notice: "Perfil atualizado!" }
      format.turbo_stream { flash.now[:notice] = "Perfil atualizado!" }
    end
  else
    render :edit, status: :unprocessable_entity
  end
end

  # AÇÃO CORRIGIDA
  def reject
    # Cria o registro de 'pass'
    current_user.likes.create(liked_id: params[:user_id], is_like: false) 
    
    # --- CORREÇÃO AQUI ---
    if params[:source] == "map"
      head :ok # Fica na tela do mapa
    else
      redirect_to lead_path
    end

  rescue ActiveRecord::RecordNotFound
    if params[:source] == "map"
      head :not_found
    else
      redirect_to lead_path
    end
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


 # Exibe a tela de solicitação
  def verification
    # Se o usuário já enviou uma foto antes, podemos mostrar um aviso ou status
  end

  # Processa o envio da foto
  def send_verification
    if params[:verification_photo].present?
      # 1. Anexa a foto ao usuário
      current_user.verification_photo.attach(params[:verification_photo])
      
      # 2. (Opcional) Você pode criar um campo 'verification_status' no banco futuramente.
      # Por enquanto, apenas ter a foto anexa já serve como "Pendente".
      
      flash[:notice] = "Solicitação enviada com sucesso! Nossa equipe analisará seu perfil."
      redirect_to my_profile_path
    else
      flash[:alert] = "Por favor, selecione uma foto para enviar."
      render :verification
    end
  end
  
end