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

          # Filtros textuais
          @users = @users.where('email ILIKE ?', "%#{params[:q]}%")              if params[:q].present?
          @users = @users.where.not(banned_at: nil)                              if params[:banned] == 'true'
          @users = @users.where(admin: true)                                     if params[:admins] == 'true'

          # Filtros demográficos
          @users = @users.where(gender: params[:gender])                         if params[:gender].present?
          @users = @users.where('address ILIKE ?', "%#{params[:city]}%")         if params[:city].present?
          @users = @users.where('address ILIKE ?', "%#{params[:state]}%")        if params[:state].present?
          @users = @users.where('address ILIKE ?', "%#{params[:country]}%")      if params[:country].present?
          @users = apply_age_range(@users, params[:age_range])                   if params[:age_range].present?
        end

        # PATCH /api/v1/admin/users/:id/update_subscription
        def update_subscription
          @user = User.find(params[:id])
          plan = Plan.find(params[:plan_id])

          @user.update!(plan: plan, premium_until: plan.name == 'Free' ? nil : 100.years.from_now)
          render json: { id: @user.id, plan_id: plan.id, plan_name: plan.name, message: 'Plano atualizado com sucesso.' }
        rescue ActiveRecord::RecordNotFound => e
          api_not_found(e.message)
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_entity
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

        private

        # age_range: "18-25", "26-35", "36-45", "46+"
        def apply_age_range(scope, range)
          case range
          when '18-25' then scope.filter_by_age(18, 25)
          when '26-35' then scope.filter_by_age(26, 35)
          when '36-45' then scope.filter_by_age(36, 45)
          when '46+'   then scope.filter_by_age(46, 120)
          else scope
          end
        end
      end
    end
  end
end
