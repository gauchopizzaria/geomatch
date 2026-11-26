module MimosHelper
  # "R$ 2,90", "R$ 1.499,90"
  def mimo_money(cents)
    number_to_currency(cents.to_i / 100.0, unit: "R$ ", separator: ",", delimiter: ".", format: "%u%n")
  end

  # "Luan Victor" → "Luan"
  def mimo_first_name(user)
    user&.display_name.to_s.split.first.presence || "a pessoa"
  end

  # "Maria Clara" → "MC"
  def mimo_initials(user)
    parts = user&.display_name.to_s.split
    letters = parts.size > 1 ? [ parts.first, parts.last ] : parts.first(1)
    letters.map { |part| part[0] }.join.upcase.presence || "?"
  end

  # Foto de quem enviou; sem foto real, as iniciais no círculo dourado (como no mockup)
  def mimo_avatar(user, css_class)
    if user&.has_real_avatar? || user&.album_photos&.attached?
      image_tag user.avatar_url, class: "#{css_class} has-photo", alt: ""
    else
      content_tag(:span, mimo_initials(user), class: css_class, aria: { hidden: true })
    end
  end

  # Regras da tela "Como funcionam os Mimos?" — lidas das constantes que o sistema aplica,
  # para o texto nunca dizer uma coisa e a regra fazer outra
  def mimo_fee_percent
    "#{(MimoFeeCalculator::SERVICE_FEE_RATE * 100).to_i}%"
  end

  def mimo_hold_days
    (UserWallet::RECEIVED_MIMO_HOLD / 1.day).to_i
  end

  def mimo_withdraw_minimum
    mimo_money(WithdrawalService::MINIMUM_AMOUNT_CENTS).sub(",00", "")
  end
end
