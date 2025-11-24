# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!

  # Página do mapa
  def discover
    @nearby_users = DiscoveryService.new(current_user).find_nearby_users
  end

  # Endpoint JSON para retornar usuários próximos
  def nearby
    if params[:latitude].present? && params[:longitude].present?
      current_user.update(
        latitude: params[:latitude],
        longitude: params[:longitude]
      )
    end

    users = DiscoveryService.new(current_user).find_nearby_users(10)

    render json: users.as_json(
      only: [:id, :username, :latitude, :longitude],
      methods: [:avatar_url]
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

    if @user.update(user_params)
      redirect_to edit_profile_path, notice: "Perfil atualizado com sucesso!"
    else
      render :edit, status: :unprocessable_entity
    end
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
      :gender,
      :interested_in,
      hobbies_list: [] # ← RECEBE ARRAY!
    )
  end
end
