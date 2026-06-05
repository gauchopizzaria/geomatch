require "open-uri"

class ImageModerationService
  # Níveis de SafeSearch do Google Vision que configuram rejeição automática
  REJECT_LIKELIHOODS = %i[POSSIBLE LIKELY VERY_LIKELY].freeze

  def self.analyze_image(image_url, expected_name = nil)
    image_annotator = Google::Cloud::Vision.image_annotator

    image_content = URI.open(image_url) { |f| f.read }

    vision_response = image_annotator.batch_annotate_images(
      requests: [
        {
          image:    { content: image_content },
          features: [
            { type: :SAFE_SEARCH_DETECTION },
            { type: :FACE_DETECTION },
            { type: :TEXT_DETECTION }
          ]
        }
      ]
    )

    response = vision_response.responses.first

    # --- 1. Conteúdo explícito ---
    safe = response.safe_search_annotation
    if safe && ([safe.adult, safe.violence, safe.racy].any? { |l| REJECT_LIKELIHOODS.include?(l) })
      Rails.logger.info "[ImageModerationService] Conteúdo explícito detectado (adult=#{safe.adult} violence=#{safe.violence} racy=#{safe.racy})"
      return { status: :rejected, score: 0.1, details: { reason: "explicit_content" } }
    end

    # --- 2. Rosto ---
    if response.face_annotations.empty?
      Rails.logger.info "[ImageModerationService] Nenhum rosto detectado na imagem."
      return { status: :rejected, score: 0.0, details: { reason: "no_face_detected" } }
    end

    # --- 3. OCR — nome esperado no texto da foto ---
    extracted_raw  = response.text_annotations.first&.description.to_s
    extracted_text = normalize(extracted_raw)
    name_found     = name_present?(extracted_text, expected_name)

    unless name_found
      Rails.logger.info "[ImageModerationService] Nome '#{expected_name}' não encontrado no texto extraído."
      return {
        status:  :rejected,
        score:   0.0,
        details: { reason: "name_not_found_in_photo", extracted_text: extracted_raw }
      }
    end

    Rails.logger.info "[ImageModerationService] Imagem aprovada para '#{expected_name}'."
    { status: :approved, score: 0.99, details: { reason: "verified" } }

  rescue StandardError => e
    Rails.logger.error "[ImageModerationService] Erro ao chamar Google Vision API: #{e.class} — #{e.message}"
    { status: :manual_review, score: 0.0, details: { reason: "api_error", error: e.message } }
  end

  # ---- helpers privados ----

  def self.normalize(str)
    str.to_s
       .unicode_normalize(:nfd)
       .gsub(/\p{Mn}/, "")
       .downcase
  end
  private_class_method :normalize

  def self.name_present?(extracted_text, expected_name)
    return true if expected_name.blank?

    normalized_name       = normalize(expected_name)
    first_name            = normalized_name.split.first.to_s

    extracted_text.include?(normalized_name) || extracted_text.include?(first_name)
  end
  private_class_method :name_present?
end
