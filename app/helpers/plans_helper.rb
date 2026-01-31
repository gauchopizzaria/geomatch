module PlansHelper
  def render_plan_feature(plan, feature_key)
    features = plan.features || {}
    value = features[feature_key]

    case feature_key.to_s
    when "direct_messages"
      render_direct_messages(value)
    else
      render_generic_feature(value)
    end
  end

  private

  def render_direct_messages(dm)
    return content_tag(:span, "—", class: "icon-neutral") if dm.nil?

    unless dm["enabled"]
      return content_tag(
        :span,
        "Bloqueadas (upgrade ou R$ 1,99 por mensagem)",
        class: "text-value"
      )
    end

    if dm["daily_limit"].nil?
      content_tag(:span, "Mensagens diretas ilimitadas", class: "text-value")
    else
      content_tag(
        :span,
        "#{dm['daily_limit']} mensagens diretas por dia",
        class: "text-value"
      )
    end
  end

  def render_generic_feature(value)
    if value == true
      content_tag(:span, class: "icon-yes") do
        tag.svg(
          width: 20,
          height: 20,
          viewBox: "0 0 24 24",
          fill: "none",
          stroke: "currentColor",
          "stroke-width": 3,
          "stroke-linecap": "round",
          "stroke-linejoin": "round"
        ) do
          tag.polyline(points: "20 6 9 17 4 12")
        end
      end
    elsif value == false
      content_tag(:span, class: "icon-no") do
        tag.svg(
          width: 16,
          height: 16,
          viewBox: "0 0 24 24",
          fill: "none",
          stroke: "currentColor",
          "stroke-width": 3,
          "stroke-linecap": "round",
          "stroke-linejoin": "round"
        ) do
          tag.line(x1: 18, y1: 6, x2: 6, y2: 18) +
          tag.line(x1: 6, y1: 6, x2: 18, y2: 18)
        end
      end
    elsif value.nil?
      content_tag(:span, "—", class: "icon-neutral")
    else
      content_tag(:span, value.to_s, class: "text-value")
    end
  end
end
