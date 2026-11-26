# O que a pessoa escolheu para enviar, antes de virar uma MimoTransaction:
#   - um mimo do catálogo num dos níveis ("Rosa" no Especial = "rosa vermelha", R$ 4,90), ou
#   - o "Mimo do seu jeito": o texto que ela digitou e o valor que ela escolheu.
#
# Os serviços de pagamento (MimoWalletPaymentService / MimoPaymentService) recebem a
# seleção já validada: preço, nome e ícone saem daqui, nunca do que o navegador mandou.
class MimoSelection
  class InvalidError < StandardError; end

  CUSTOM_MIN_CENTS = 500     # R$ 5,00
  CUSTOM_MAX_CENTS = 50_000  # R$ 500,00
  CUSTOM_LABEL_MAX = 40
  MESSAGE_MAX      = 80

  attr_reader :mimo_item, :tier, :label, :price_cents

  def initialize(mimo_item:, tier:, label:, price_cents:)
    @mimo_item   = mimo_item
    @tier        = tier
    @label       = label
    @price_cents = price_cents
  end

  # Catálogo. Sem nível (app mobile antigo, que só manda mimo_item_id) vale o Simples:
  # é o preço do próprio item, o mesmo que o catálogo JSON mostra em price_formatted.
  def self.from_item(mimo_item, tier_key = nil)
    raise InvalidError, "este Mimo não está disponível no momento" unless mimo_item&.active?

    if tier_key.present? || mimo_item.tiered?
      key  = tier_key.presence || MimoItem::TIER_KEYS.first
      data = mimo_item.tier(key)
      raise InvalidError, "escolha Simples, Especial ou Premium" unless data

      new(mimo_item: mimo_item, tier: data[:key], label: data[:label], price_cents: data[:price_cents])
    else
      new(mimo_item: mimo_item, tier: nil, label: mimo_item.name, price_cents: mimo_item.price_cents)
    end
  end

  # "Mimo do seu jeito"
  def self.custom(label:, amount_cents:)
    text  = label.to_s.squish
    cents = amount_cents.to_i

    raise InvalidError, "Escreva o que você quer dar." if text.empty?
    raise InvalidError, "Use até #{CUSTOM_LABEL_MAX} caracteres no nome do mimo." if text.length > CUSTOM_LABEL_MAX
    unless cents.between?(CUSTOM_MIN_CENTS, CUSTOM_MAX_CENTS)
      raise InvalidError, "O valor precisa ficar entre #{format_money(CUSTOM_MIN_CENTS)} e #{format_money(CUSTOM_MAX_CENTS)}."
    end

    new(mimo_item: nil, tier: nil, label: text, price_cents: cents)
  end

  def self.format_money(cents)
    Money.new(cents, "BRL").format
  end

  def custom?
    mimo_item.nil?
  end

  def icon
    mimo_item&.icon
  end

  # Nome para o recibo/descrição do pagamento: "Rosa — rosa vermelha" ou o texto digitado
  def description
    return label if custom? || tier.nil?

    "#{mimo_item.name} — #{label}"
  end

  # Recadinho: até MESSAGE_MAX caracteres, sem espaços sobrando
  def self.clean_message(message)
    text = message.to_s.strip
    raise InvalidError, "O recadinho pode ter até #{MESSAGE_MAX} caracteres." if text.length > MESSAGE_MAX

    text.presence
  end
end
