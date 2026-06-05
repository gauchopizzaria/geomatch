class UserMailer < ApplicationMailer
  REJECTION_REASONS = {
    "no_face_detected"        => "Nenhum rosto foi identificado na foto enviada. Certifique-se de que seu rosto esteja claramente visível.",
    "explicit_content"        => "A imagem contém conteúdo inapropriado e não pôde ser aceita.",
    "name_not_found_in_photo" => "Seu nome não foi encontrado na foto de verificação. Segure um papel com seu nome escrito de forma legível.",
    "api_error"               => "Ocorreu um erro ao processar sua foto. Por favor, tente novamente."
  }.freeze

  def verification_rejected(user)
    @user             = user
    @rejection_reason = friendly_reason(user.ai_moderation_details)
    mail(to: user.email, subject: "Sua foto de verificação não foi aprovada — GeoMatch")
  end

  private

  def friendly_reason(details)
    return "Motivo não especificado." if details.blank?

    raw_reason = details.is_a?(Hash) ? (details["reason"] || details[:reason]).to_s : ""
    REJECTION_REASONS.fetch(raw_reason, "Motivo não especificado.")
  end
end
