module Api
  module V1
    module Admin
      # GET   /api/v1/admin/users          → lista paginada
      # PATCH /api/v1/admin/users/:id/ban  → bane ou desbane a conta
      class UsersController < BaseController
        PAGE_SIZE = 30

        def index
          @users = User
            .includes(:plan)
            .order(created_at: :desc)
            .page(params[:page])
            .per(PAGE_SIZE)

          # Filtros opcionais via query string
          @users = @users.where('email ILIKE ?', "%#{params[:q]}%") if params[:q].present?
          @users = @users.where.not(banned_at: nil)                 if params[:banned] == 'true'
          @users = @users.where(admin: true)                         if params[:admins] == 'true'
        end

        # PATCH /api/v1/admin/users/:id/ban
        def ban
          @user = User.find(params[:id])

          # Impede banir outro admin acidentalmente
          if @user.admin?
            return render json: { error: 'Não é possível banir um administrador.' }, status: :unprocessable_entity
          end

          if @user.banned?
            @user.unban!
            render json: { id: @user.id, banned: false, banned_at: nil, message: 'Conta reativada.' }
          else
            @user.ban!
            render json: { id: @user.id, banned: true, banned_at: @user.banned_at.iso8601, message: 'Conta suspensa.' }
          end
        rescue ActiveRecord::RecordNotFound
          api_not_found('Usuário não encontrado.')
        end
      end
    end
  end
end
