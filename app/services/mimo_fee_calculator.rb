# Calcula como o valor bruto de um Mimo (o que o remetente paga) é dividido
# entre a taxa do Mercado Pago, a margem da plataforma e o valor líquido
# creditado na carteira do destinatário.
#
# Regra da tela "Como funcionam os Mimos?": 12% cobre os custos do serviço e quem
# recebe fica com 88% — R$ 100,00 viram R$ 88,00 na carteira, pague quem enviou
# com o saldo ou com Pix/cartão. Quando o pagamento passa pelo Mercado Pago, a taxa
# dele sai de dentro desses 12% (o resto é a margem da plataforma); com o saldo da
# carteira não há taxa do MP e os 12% inteiros ficam com a plataforma.
#
# Serviço puro — sem I/O, sem persistência. Recebe centavos, devolve centavos.
# Isolado para que a fórmula de taxas possa ser testada e ajustada num único
# lugar, sem tocar em MimoPaymentService ou nos models.
class MimoFeeCalculator
  SERVICE_FEE_RATE = BigDecimal("0.12")   # 12% — o que a tela informa
  MP_FEE_RATE      = BigDecimal("0.0499") # 4,99% — custo de processamento do Mercado Pago

  Breakdown = Struct.new(
    :gross_cents, :mp_fee_cents, :platform_fee_cents, :receiver_value_cents,
    keyword_init: true
  )

  def self.call(gross_cents, apply_mp_fee: true)
    new(gross_cents, apply_mp_fee: apply_mp_fee).call
  end

  # "R$ 100,00 → R$ 88,00": o que entra na carteira de quem recebe
  def self.receiver_value_cents(gross_cents)
    call(gross_cents).receiver_value_cents
  end

  def initialize(gross_cents, apply_mp_fee: true)
    @gross_cents  = gross_cents.to_i
    @apply_mp_fee = apply_mp_fee
  end

  def call
    raise ArgumentError, "gross_cents deve ser positivo" unless @gross_cents.positive?

    service_fee  = round_cents(@gross_cents * SERVICE_FEE_RATE)
    # Pagamento com saldo interno da carteira não passa pelo Mercado Pago —
    # não há taxa de processamento de cartão/Pix (ver MimoWalletPaymentService).
    mp_fee       = @apply_mp_fee ? [ round_cents(@gross_cents * MP_FEE_RATE), service_fee ].min : 0
    platform_fee = service_fee - mp_fee

    Breakdown.new(
      gross_cents: @gross_cents,
      mp_fee_cents: mp_fee,
      platform_fee_cents: platform_fee,
      receiver_value_cents: @gross_cents - service_fee
    )
  end

  private

  # Arredondamento bancário (round-half-up) sobre BigDecimal — evita o erro de
  # ponto flutuante de multiplicar Integer por Float diretamente.
  def round_cents(value)
    value.round(0, BigDecimal::ROUND_HALF_UP).to_i
  end
end
