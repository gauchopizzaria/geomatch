# frozen_string_literal: true

module Api
  module V1
    module Admin
      # GET    /api/v1/admin/moderation                    → lista pendentes
      # PATCH  /api/v1/admin/moderation/:id/verify_user   → aprova verificação
      # PATCH  /api/v1/admin/moderation/:id/reject_photo  → recusa foto
      # PATCH  /api/v1/admin/moderation/:id/ban_user      → bane conta
      class ModerationController < BaseController
        PAGE_SIZE = 20

        # Usuários com verification_photo anexada e ainda não verificados
        def index
          pending_users  = pending_scope.page(params[:page]).per(PAGE_SIZE)
          verified_users = verified_scope.page(params[:page]).per(PAGE_SIZE)

          Rails.logger.debug "[Moderation#index] Pendentes encontrados: #{pending_scope.count}"
          Rails.logger.debug "[Moderation#index] Verificados encontrados: #{verified_scope.count}"

          render json: {
            pending:  pending_users.map  { |u| serialize(u) },
            verified: verified_users.map { |u| serialize(u) },
            pagination: {
              current_page: pending_users.current_page,
              total_pages:  pending_users.total_pages,
              total_count:  pending_users.total_count
            }
          }
        rescue => e
          Rails.logger.error "[Moderation#index] Erro: #{e.message}"
          render json: { pending: [], verified: [], pagination: { current_page: 1, total_pages: 0, total_count: 0 } }, status: :ok
        end

        # Marca usuário como verificado e remove a foto de verificação
        def verify_user
          user = User.find(params[:id])
          user.update!(verified: true)
          user.verification_photo.purge_later if user.verification_photo.attached?
          render json: { id: user.id, verified: true, message: 'Usuário verificado com sucesso.' }
        rescue ActiveRecord::RecordNotFound
          api_not_found('Usuário não encontrado.')
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        # Remove a foto de verificação (sem verificar)
        def reject_photo
          user = User.find(params[:id])
          reason = params[:reason].presence || 'Foto não corresponde ao perfil.'
          user.verification_photo.purge_later if user.verification_photo.attached?
          Rails.logger.info "[MODERATION] Foto recusada para User##{user.id} (#{user.email}). Motivo: #{reason}"
          render json: { id: user.id, message: 'Foto removida.' }
        rescue ActiveRecord::RecordNotFound
          api_not_found('Usuário não encontrado.')
        end

        # Bane a conta e remove a foto de verificação
        def ban_user
          user = User.find(params[:id])
          return render json: { error: 'Não é possível banir um administrador.' },
                        status: :unprocessable_entity if user.admin?

          user.ban!
          user.verification_photo.purge_later if user.verification_photo.attached?
          render json: { id: user.id, banned: true, message: 'Conta banida e foto removida.' }
        rescue ActiveRecord::RecordNotFound
          api_not_found('Usuário não encontrado.')
        end

        private

        def pending_scope
          User.where(verified: false, banned_at: nil)
              .joins(:verification_photo_attachment)
              .order(created_at: :desc)
        end

        def verified_scope
          User
            .where(verified: true, banned_at: nil)
            .includes(avatar_attachment: :blob)
            .order(updated_at: :desc)
        end

        def serialize(user)
          {
            id:                       user.id,
            name:                     user.display_name,
            email:                    user.email,
            created_at:               user.created_at.iso8601,
            avatar_url:               blob_path(user.avatar),
            verification_photo_url:   blob_path(user.verification_photo)
          }
        end

        def blob_path(attachment)
          return nil unless attachment.attached?
          Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
        end
      end
    end
  end
end
