# Áudio (mensagem de voz) e foto nas mensagens do chat.
#
# Não há coluna nova em `messages`: o arquivo é um anexo do Active Storage e o que o
# balão precisa para ser desenhado (duração, desenho da onda, tamanho da foto) fica no
# metadata do blob — em produção o banco é ajustado à mão, e assim o recurso funciona
# sem migration. O `content` recebe um rótulo ("🎤 Mensagem de voz (0:07)", "📷 Foto"),
# então lista de conversas, push, citação e API seguem funcionando sem saber de mídia.
module MessageMedia
  extend ActiveSupport::Concern

  # O que o navegador grava (MediaRecorder) → extensão do arquivo
  AUDIO_TYPES = {
    "audio/mp4"   => "m4a",
    "audio/x-m4a" => "m4a",
    "audio/aac"   => "aac",
    "audio/mpeg"  => "mp3",
    "audio/webm"  => "webm",
    "audio/ogg"   => "ogg"
  }.freeze
  PHOTO_TYPES = { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.freeze
  # O que a conferência do conteúdo vê num áudio de verdade: o contêiner é o mesmo do
  # vídeo (webm aparece como application/x-matroska; mp4 como video/mp4 ou quicktime)
  AUDIO_CONTAINERS = %w[audio/ video/ application/ogg application/x-matroska application/mp4].freeze

  AUDIO_MAX_SIZE     = 8.megabytes
  AUDIO_MIN_DURATION = 1      # segundos — menos que isso é toque sem querer
  AUDIO_MAX_DURATION = 180    # segundos — o gravador para sozinho aqui (chat/voice_recorder.js)
  AUDIO_PEAKS        = 32     # barras da onda no balão
  PHOTO_MAX_SIZE     = 10.megabytes

  # Tocam em qualquer aparelho como foram gravados; o resto (webm/ogg) é convertido na
  # entrega quando o arquivo está no Cloudinary — o iPhone não toca webm em versões antigas.
  UNIVERSAL_AUDIO_TYPES = %w[audio/mp4 audio/x-m4a audio/aac audio/mpeg].freeze

  included do
    has_one_attached :audio
    has_one_attached :photo

    before_validation :label_media, on: :create
  end

  def audio?
    audio.attached?
  end

  def photo?
    photo.attached?
  end

  def media?
    audio? || photo?
  end

  def kind
    return "audio" if audio?
    return "photo" if photo?

    "text"
  end

  # --- Anexar (MessagesController#create) -------------------------------------------
  # O arquivo sobe ANTES de a mensagem ser salva: se o armazenamento recusar, a pessoa
  # recebe o erro e nenhuma mensagem sem arquivo fica na conversa — e quando o broadcast
  # sai (after_create_commit) o endereço do arquivo já responde.

  def attach_voice(file, duration:, peaks: nil)
    return media_error("O áudio não chegou. Tente gravar de novo.") unless upload?(file)
    return media_error("O áudio é grande demais.") if file.size > AUDIO_MAX_SIZE

    type = base_type(file.content_type)
    unless AUDIO_TYPES.key?(type) && plausible_bytes?(file, AUDIO_CONTAINERS)
      return media_error("Formato de áudio não aceito.")
    end

    seconds = duration.to_f
    return media_error("Áudio curto demais.") if seconds < AUDIO_MIN_DURATION

    upload_media(:audio, file, "voz.#{AUDIO_TYPES.fetch(type)}", type,
                 "gm_duration" => [ seconds, AUDIO_MAX_DURATION ].min.round(1),
                 "gm_peaks"    => normalize_peaks(peaks))
  end

  def attach_picture(file, width: nil, height: nil)
    return media_error("A foto não chegou. Tente de novo.") unless upload?(file)
    return media_error("A foto é grande demais.") if file.size > PHOTO_MAX_SIZE

    type = base_type(file.content_type)
    unless PHOTO_TYPES.key?(type) && plausible_bytes?(file, %w[image/])
      return media_error("Formato de foto não aceito. Envie JPG, PNG ou WebP.")
    end

    upload_media(:photo, file, "foto.#{PHOTO_TYPES.fetch(type)}", type,
                 "gm_width" => width.to_i.clamp(0, 10_000), "gm_height" => height.to_i.clamp(0, 10_000))
  end

  # A mensagem não foi salva depois de o arquivo subir: não deixa o arquivo órfão.
  def discard_uploaded_media
    Array(@uploaded_media).each do |blob|
      blob.purge_later
    rescue StandardError => e
      Rails.logger.warn "[Message#discard_uploaded_media] blob=#{blob.id} #{e.class}: #{e.message}"
    end
    @uploaded_media = nil
  end

  # --- O que o balão precisa (show.html.erb e chat_logic.js) -------------------------

  def audio_duration
    audio? ? audio.blob.metadata["gm_duration"].to_f : 0.0
  end

  def audio_peaks
    return [] unless audio?

    normalize_peaks(audio.blob.metadata["gm_peaks"])
  end

  def audio_preview
    return nil unless audio?

    plain = blob_path(audio)
    { url: converted_audio_url || plain, fallback_url: plain, duration: audio_duration, peaks: audio_peaks }
  end

  def photo_preview
    return nil unless photo?

    meta = photo.blob.metadata
    { url: blob_path(photo), width: meta["gm_width"].to_i, height: meta["gm_height"].to_i }
  end

  # "0:07" — segundos completos, como o cronômetro do gravador (1,7 s é "0:01")
  def self.duration_label(seconds)
    total = seconds.to_f.floor
    format("%d:%02d", total / 60, total % 60)
  end

  private

  def label_media
    if audio?
      self.content = "🎤 Mensagem de voz (#{MessageMedia.duration_label(audio_duration)})"
    elsif photo?
      self.content = "📷 Foto"
    end
  end

  def upload_media(name, file, filename, content_type, metadata)
    io = file.tempfile
    io.rewind
    # identify: false — o tipo já foi conferido acima, e a detecção automática troca
    # audio/webm e audio/mp4 por video/* (o contêiner é o mesmo)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: io, filename: filename, content_type: content_type, identify: false, metadata: metadata
    )
    (@uploaded_media ||= []) << blob
    public_send(name).attach(blob)
    true
  rescue StandardError => e
    Rails.logger.error "[Message#upload_media] #{name} match=#{match_id} sender=#{sender_id} #{e.class}: #{e.message}"
    media_error(name == :audio ? "Não foi possível enviar o áudio agora." : "Não foi possível enviar a foto agora.")
  end

  def media_error(text)
    errors.add(:base, text)
    false
  end

  def upload?(file)
    file.respond_to?(:tempfile) && file.respond_to?(:content_type) && file.size.to_i.positive?
  end

  # "audio/webm;codecs=opus" → "audio/webm"
  def base_type(content_type)
    content_type.to_s.split(";").first.to_s.strip.downcase
  end

  # O tipo declarado vem de quem envia. Aqui o começo do arquivo é conferido: o que
  # claramente é outra coisa (página, imagem no lugar do áudio…) não entra. Arquivo
  # que a detecção não reconhece passa — os gravadores dos navegadores variam.
  def plausible_bytes?(file, accepted_prefixes)
    io = file.tempfile
    io.rewind
    sniffed = Marcel::MimeType.for(io)
    io.rewind
    sniffed == "application/octet-stream" || accepted_prefixes.any? { |prefix| sniffed.start_with?(prefix) }
  end

  # Aceita "12,80,45" (formulário) ou [12, 80, 45] (metadata): até AUDIO_PEAKS valores de 0 a 100
  def normalize_peaks(peaks)
    values = peaks.is_a?(String) ? peaks.split(",") : Array(peaks)
    values.first(AUDIO_PEAKS).map { |value| value.to_i.clamp(0, 100) }
  end

  def blob_path(attachment)
    Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
  end

  # No Cloudinary, pedir o arquivo com outra extensão converte o áudio na entrega.
  # Só para o que não toca em todo lugar; qualquer problema volta ao arquivo original
  # (o player também tenta o original se este endereço falhar).
  def converted_audio_url
    blob = audio.blob
    return nil if UNIVERSAL_AUDIO_TYPES.include?(blob.content_type)

    service = blob.service
    return nil unless service.class.name == "ActiveStorage::Service::CloudinaryService"
    return nil unless service.method(:url).parameters.any? { |type, _| type == :keyrest }

    blob.url(format: "mp3")
  rescue StandardError => e
    Rails.logger.warn "[Message#converted_audio_url] message=#{id} #{e.class}: #{e.message}"
    nil
  end
end
