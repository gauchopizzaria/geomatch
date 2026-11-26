class MimoItem < ApplicationRecord
  # Categorias do catálogo, na ordem da tela "Enviar um Mimo". title é o cabeçalho
  # da seção ("MIMOS RÁPIDOS"); chip é o botão curto do topo ("Rápidos").
  CATEGORIES = [
    { key: "rapidos",   title: "Mimos rápidos",       chip: "Rápidos" },
    { key: "bebidas",   title: "Bebidas",             chip: "Bebidas" },
    { key: "comidas",   title: "Comidas",             chip: "Comidas" },
    { key: "beleza",    title: "Saúde & Beleza",      chip: "Beleza" },
    { key: "presentes", title: "Presentes & Estilo",  chip: "Presentes" },
    { key: "fitness",   title: "Fitness",             chip: "Fitness" },
    { key: "role",      title: "Rolê & Experiências", chip: "Rolê" },
    { key: "vip",       title: "VIP",                 chip: "VIP" }
  ].freeze
  CATEGORY_KEYS = CATEGORIES.map { |category| category[:key] }.freeze

  # Os três níveis de todo mimo do catálogo. O Especial já vem marcado na tela.
  TIER_KEYS    = %w[simples especial premium].freeze
  TIER_NAMES   = { "simples" => "Simples", "especial" => "Especial", "premium" => "Premium" }.freeze
  DEFAULT_TIER = "especial".freeze

  monetize :price_cents
  monetize :receiver_value_cents, as: "receiver_value"

  has_many :mimo_transactions, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :price_cents, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :receiver_value_cents, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :category, inclusion: { in: CATEGORY_KEYS }, allow_nil: true

  # Margem da plataforma (price_cents - receiver_value_cents) não pode ser negativa —
  # a plataforma nunca repassa mais do que cobrou do remetente.
  validate :receiver_value_cannot_exceed_price
  validate :tiers_must_be_complete

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  # Itens do catálogo novo (com categoria e níveis), agrupados na ordem da tela
  def self.catalog
    items = active.where(category: CATEGORY_KEYS).ordered.to_a.select(&:tiered?).group_by(&:category)
    CATEGORIES.filter_map do |category|
      list = items[category[:key]]
      category.merge(items: list) if list.present?
    end
  end

  def tiered?
    tiers.is_a?(Array) && tiers.size == TIER_KEYS.size
  end

  # { key:, name: "Especial", label: "rosa vermelha", price_cents: 490 }
  def tier(key)
    data = Array(tiers).find { |entry| entry["key"] == key.to_s }
    return nil unless data

    { key: data["key"], name: TIER_NAMES[data["key"]], label: data["label"].to_s, price_cents: data["price_cents"].to_i }
  end

  def tier_list
    TIER_KEYS.filter_map { |key| tier(key) }
  end

  # "a partir de" do card: o nível mais barato (Simples)
  def starting_price_cents
    tier_list.map { |entry| entry[:price_cents] }.min || price_cents
  end

  def vip?
    category == "vip"
  end

  private

  def receiver_value_cannot_exceed_price
    return if receiver_value_cents.nil? || price_cents.nil?

    if receiver_value_cents > price_cents
      errors.add(:receiver_value_cents, "não pode ser maior que o preço cobrado do remetente")
    end
  end

  # Mimo sem níveis (o catálogo antigo) continua válido; com níveis, precisa dos três,
  # cada um com nome e preço positivo
  def tiers_must_be_complete
    return if tiers.blank?

    keys = Array(tiers).map { |entry| entry.is_a?(Hash) ? entry["key"] : nil }
    unless keys.sort == TIER_KEYS.sort
      errors.add(:tiers, "precisa ter os níveis #{TIER_KEYS.join(', ')}")
      return
    end

    Array(tiers).each do |entry|
      if entry["label"].to_s.strip.empty? || entry["price_cents"].to_i <= 0
        errors.add(:tiers, "#{entry['key']}: informe o nome e um preço maior que zero")
      end
    end
  end
end
