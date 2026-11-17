module MatchesHelper
  WEEKDAYS_SHORT = %w[Dom Seg Ter Qua Qui Sex Sáb].freeze
  WEEKDAYS_LONG  = %w[Domingo Segunda-feira Terça-feira Quarta-feira Quinta-feira Sexta-feira Sábado].freeze
  MONTHS = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze

  # Sugestões acima do campo da conversa (tocar preenche o campo)
  QUICK_REPLIES = [ "Oi! Tudo bem?", "E aí, beleza?", "Como tá seu dia?" ].freeze

  # Lista de conversas: "12:48" hoje, "Ontem", "Seg" na mesma semana, senão "12/10"
  def conversation_time_label(time)
    return "" unless time

    date  = time.to_date
    today = Date.current
    if date == today then time.strftime("%H:%M")
    elsif date == today - 1 then "Ontem"
    elsif date > today - 7 then WEEKDAYS_SHORT[date.wday]
    else date.strftime("%d/%m")
    end
  end

  # Separador de dia na conversa: "Hoje", "Ontem", "Segunda-feira", senão "12 de outubro"
  def chat_day_label(date)
    today = Date.current
    if date == today then "Hoje"
    elsif date == today - 1 then "Ontem"
    elsif date > today - 7 then WEEKDAYS_LONG[date.wday]
    else
      label = "#{date.day} de #{MONTHS[date.month - 1]}"
      date.year == today.year ? label : "#{label} de #{date.year}"
    end
  end

  # Abaixo do nome no topo da conversa ("Ativo agora" respeita o modo invisível)
  def chat_status_label(user)
    online_now_label(user) || "Offline"
  end

  # Chip do começo da conversa. A distância é a de quando a conexão aconteceu
  # (Match#distance_m); conversas antigas ou de quem não compartilha a
  # localização mostram como ela começou.
  def connection_chip_text(match, viewer)
    other    = match.other_user(viewer)
    distance = match.has_attribute?(:distance_m) ? match.distance_m : nil
    sharing  = [ viewer, other ].none? { |person| person.share_location == false }

    if distance && sharing
      distance < 300 ? "Vocês se conectaram a menos de 300 m" : "Vocês se conectaram a #{approx_km_label(distance / 1000.0)}"
    elsif mutual_match?(viewer, other)
      "Vocês deram match"
    elsif match.user_id == viewer.id
      "Você iniciou a conversa"
    else
      "#{other.display_name.split.first} iniciou a conversa"
    end
  end

  # --- Balões de mídia (o chat_logic.js monta o mesmo HTML para o que chega ao vivo) ---

  AUDIO_ICONS = (
    '<svg class="msg-audio-icon-play" viewBox="0 0 24 24" aria-hidden="true"><path d="M8.5 5.6v12.8a1 1 0 0 0 1.52.85l10.2-6.4a1 1 0 0 0 0-1.7l-10.2-6.4a1 1 0 0 0-1.52.85z"/></svg>' \
    '<svg class="msg-audio-icon-pause" viewBox="0 0 24 24" aria-hidden="true"><rect x="6.5" y="5" width="4" height="14" rx="1.2"/><rect x="13.5" y="5" width="4" height="14" rx="1.2"/></svg>'
  ).html_safe.freeze

  # Mensagem de voz: tocar/pausar, onda (uma barra por pico) e duração
  def chat_audio_tag(message)
    audio = message.audio_preview
    meta  = content_tag(:span, class: "msg-audio-meta") do
      content_tag(:span, "", class: "msg-audio-dot") +
        content_tag(:span, MessageMedia.duration_label(audio[:duration]), class: "msg-audio-time")
    end

    content_tag(:span, class: "msg-audio",
                       data: { url: audio[:url], fallback_url: audio[:fallback_url], duration: audio[:duration] }) do
      content_tag(:button, AUDIO_ICONS, type: "button", class: "msg-audio-play", aria: { label: "Tocar áudio" }) +
        content_tag(:span, content_tag(:span, audio_wave_bars(audio[:peaks]), class: "msg-audio-wave") + meta,
                    class: "msg-audio-body")
    end
  end

  # Sempre AUDIO_PEAKS barras: os picos gravados são esticados/encolhidos para caber
  def audio_wave_bars(peaks)
    count = MessageMedia::AUDIO_PEAKS
    bars = Array.new(count) do |index|
      peak = peaks.empty? ? 0 : peaks[(index * peaks.size / count.to_f).floor].to_i
      # 14% é a barra mínima (silêncio); 100% é a altura toda da onda
      tag.i(style: "height:#{[ peak, 14 ].max}%")
    end
    safe_join(bars)
  end

  def chat_photo_tag(message)
    photo = message.photo_preview
    size  = photo[:width].positive? && photo[:height].positive? ? { width: photo[:width], height: photo[:height] } : {}

    image_tag(photo[:url], { class: "msg-photo", alt: "Foto", loading: "lazy", draggable: "false" }.merge(size))
  end

  private

  def mutual_match?(viewer, other)
    Like.exists?(liker_id: viewer.id, liked_id: other.id) && Like.exists?(liker_id: other.id, liked_id: viewer.id)
  end
end
