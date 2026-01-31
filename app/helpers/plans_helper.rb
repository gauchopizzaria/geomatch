module PlansHelper
  def render_plan_feature(plan, feature_key)
    features = plan.features || {}
    value = features[feature_key]

    # Decide qual renderizador usar baseado na chave (feature)
    case feature_key.to_s
    when "direct_messages"
      render_direct_messages(value)
    when "likes_right_limit"
      # Exibe valor ou infinito se não tiver limite
      value.present? ? content_tag(:span, value.to_s, class: "text-value") : render_infinity
    when "likes_right_unlimited", "likes_left_unlimited"
      # Se for true, mostra infinito. Se false, mostra traço.
      value === true ? render_infinity : render_dash
    else
      render_generic_feature(value)
    end
  end

  private

  # Renderiza o símbolo de infinito com estilo
  def render_infinity
    content_tag(:span, "∞", class: "text-value text-infinity", style: "font-size: 1.5rem; line-height: 1;")
  end

  # Renderiza o traço (quando não tem o recurso)
  def render_dash
    content_tag(:span, "—", class: "icon-neutral")
  end

  def render_direct_messages(dm)
    return render_dash if dm.nil?

    # Caso 1: Mensagens bloqueadas/não incluídas
    unless dm["enabled"]
      return content_tag(:span, "Não incluído", class: "text-muted")
    end

    # Caso 2: Ilimitado (Gold)
    if dm["daily_limit"].nil?
      return render_infinity
    end

    # Caso 3: Com limite (Plus)
    content_tag(
      :span,
      "#{dm['daily_limit']} por dia",
      class: "text-value"
    )
  end

  def render_generic_feature(value)
    if value == true
      # Ícone de Check (Sim)
      content_tag(:span, class: "icon-yes") do
        tag.svg(width: 20, height: 20, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", stroke_width: 3) do
          tag.polyline(points: "20 6 9 17 4 12")
        end
      end
    elsif value == false
      # Ícone de X (Não) - Opcional, ou use render_dash
      render_dash
    elsif value.nil?
      render_dash
    else
      # Texto genérico (números, strings)
      content_tag(:span, value.to_s, class: "text-value")
    end
  end
end