class AnalyzeVerificationPhotoJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)

    unless user.verification_photo.attached?
      Rails.logger.info "[AnalyzeVerificationPhotoJob] User##{user_id} sem verification_photo anexada. Pulando."
      return
    end

    image_url = user.verification_photo.url

    result = ImageModerationService.analyze_image(image_url, user.display_name)

    user.update_columns(
      ai_moderation_status:  result[:status].to_s,
      ai_moderation_score:   result[:score],
      ai_moderation_details: result[:details]
    )

    Rails.logger.info "[AnalyzeVerificationPhotoJob] User##{user_id} moderado: status=#{result[:status]} score=#{result[:score]}"

    case result[:status]
    when :approved
      user.update(verified: true)
      Rails.logger.info "[AnalyzeVerificationPhotoJob] User##{user_id} verificado automaticamente pela IA."
    when :rejected
      user.verification_photo.purge
      UserMailer.verification_rejected(user).deliver_later
      Rails.logger.info "[AnalyzeVerificationPhotoJob] User##{user_id} foto removida pela IA (conteúdo rejeitado)."
    when :manual_review
      Rails.logger.info "[AnalyzeVerificationPhotoJob] User##{user_id} encaminhado para revisão manual."
    end

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[AnalyzeVerificationPhotoJob] User##{user_id} não encontrado. Job ignorado."

  rescue StandardError => e
    Rails.logger.error "[AnalyzeVerificationPhotoJob] Erro ao moderar User##{user_id}: #{e.class} — #{e.message}"

    User.find_by(id: user_id)&.update_columns(
      ai_moderation_status:  "error",
      ai_moderation_details: { error: e.class.to_s, message: e.message }
    )
  end
end
