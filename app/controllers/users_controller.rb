# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!

  # Página do mapa
  def discover
    # A busca inicial de usuários próximos será feita pelo JavaScript após a geolocalização
    # @nearby_users = DiscoveryService.new(current_user).find_nearby_users
  end

  # Perfil Público
  def show
    # Busca o usuário pelo ID passado na URL (params[:id])
    @user = User.find(params[:id])

  rescue ActiveRecord::RecordNotFound
    # Trata o caso de um ID inválido ou usuário inexistente
    redirect_to discover_path, alert: "Usuário não encontrado."
  end

  # Action para a nova tela de Dashboard do Perfil
  def me_profile
    @user = current_user
  end

  # Action da aba "Visualizar"
  def preview
    @user = current_user
    # Renderiza a view 'app/views/users/preview.html.erb'
  end

  # Nova tela de Descoberta (Lead/Swipe)
  def lead
    # 🚨 1. CASO SEJA POPUP DE MATCH
    # Exemplo de rota: /lead?match=true&match_id=27
    if params[:match] == "true" && params[:match_id].present?
      @match = Match.find(params[:match_id])

      # Descobre quem é o outro usuário para mostrar no popup
      @next_user =
        if @match.user_id == current_user.id
          @match.matched_user
        else
          @match.user
        end

      # Não continua buscando novos usuários — somente exibe o popup
      return
    end

    # 🚀 2. CASO NORMAL (busca próximo usuário elegível)
    liked_ids = current_user.likes.pluck(:liked_id)

    @next_user, @distance =
      AdvancedDiscoveryService.new(current_user).find_next_eligible_user(liked_ids)

    # Renderiza a view normalmente
  end

  # Endpoint JSON para retornar usuários próximos
  def nearby
    # 1. Captura os parâmetros
    latitude = params[:latitude].to_f
    longitude = params[:longitude].to_f
    range_km = params[:range].to_i.presence || 50 
    gender_filter = params[:gender]&.downcase

    # 2. Atualiza a localização do usuário atual, se fornecida
    if latitude.present? && longitude.present?
      current_user.update(
        latitude: latitude,
        longitude: longitude
      )
    end

    # 3. Validação básica (Proteção contra coordenadas 0.0, 0.0 se necessário)
    if latitude.zero? && longitude.zero?
      render json: [], status: :ok
      return
    end

    # 4. Busca usuários próximos com filtros
    # Nota: Mantive a chamada que passa o gender_filter, pois parece ser a mais completa
    users = DiscoveryService.new(current_user).find_nearby_users(range_km, gender_filter)

    # 5. Renderiza a resposta JSON formatada
    render json: users.as_json(
      only: [:id, :username, :latitude, :longitude, :avatar_url, :distance_km, :city]
    )

  rescue => e
    Rails.logger.error "Erro em /users/nearby: #{e.message}"
    render json: { error: "Erro interno ao buscar usuários próximos" },
           status: :internal_server_error
  end

  # Editar perfil
  def edit
    @user = current_user
  end

  def update
    @user = current_user

    # 1. Lida com o upload de novas fotos separadamente
    if params[:user][:album_photos].present?
      @user.album_photos.attach(params[:user][:album_photos])
    end

    # 2. Prepara os parâmetros para o update do restante do usuário
    user_update_params = user_params.except(:album_photos)

    # 3. Atualiza o restante dos atributos do usuário
    if @user.update(user_update_params)
      redirect_to edit_profile_path, notice: "Perfil atualizado com sucesso!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Ação para rejeitar um usuário
  def reject
    rejected_user = User.find(params[:user_id])
    # Exemplo simples: apenas ignora e segue
    redirect_to lead_path
  rescue ActiveRecord::RecordNotFound
    redirect_to lead_path, alert: "Usuário a ser rejeitado não encontrado."
  end

  private

  def user_params
    params.require(:user).permit(
      :avatar,
      :username,
      :bio,
      :birthdate,
      :gender,
      :share_location,
      :interested_in,
      { hobbies_list: [] },
      album_photos: []
    )
  end
end