require "rails_helper"

RSpec.describe MimoItem, type: :model do
  def tiers(*rows)
    MimoItem::TIER_KEYS.zip(rows).map { |key, (label, cents)| { "key" => key, "label" => label, "price_cents" => cents } }
  end

  def build_item(attrs = {})
    described_class.new({ name: "Rosa", icon: "🌹", category: "rapidos", price_cents: 290, receiver_value_cents: 0,
                          tiers: tiers([ "rosa", 290 ], [ "rosa vermelha", 490 ], [ "buquê de rosas", 990 ]) }.merge(attrs))
  end

  it "lê cada nível com nome, rótulo e preço; 'a partir de' é o Simples" do
    item = build_item

    expect(item.tier("especial")).to eq(key: "especial", name: "Especial", label: "rosa vermelha", price_cents: 490)
    expect(item.tier_list.map { |t| t[:key] }).to eq(%w[simples especial premium])
    expect(item.starting_price_cents).to eq(290)
    expect(item.tier("gigante")).to be_nil
  end

  it "exige os três níveis, cada um com nome e preço" do
    expect(build_item(tiers: tiers([ "rosa", 290 ], [ "rosa vermelha", 490 ]).first(2))).not_to be_valid
    expect(build_item(tiers: tiers([ "rosa", 290 ], [ "", 490 ], [ "buquê", 990 ]))).not_to be_valid
    expect(build_item(tiers: tiers([ "rosa", 0 ], [ "rosa vermelha", 490 ], [ "buquê", 990 ]))).not_to be_valid
    expect(build_item).to be_valid
  end

  it "o catálogo antigo (sem níveis e sem categoria) continua válido" do
    expect(build_item(name: "Taça de Vinho", category: nil, tiers: [])).to be_valid
  end

  it "só aceita as categorias da tela" do
    expect(build_item(category: "carros")).not_to be_valid
  end

  it ".catalog agrupa os ativos com níveis na ordem das categorias" do
    build_item(name: "Coroa", category: "vip", position: 1).save!
    build_item(name: "Rosa", category: "rapidos", position: 2).save!
    build_item(name: "Café", category: "bebidas", position: 3, active: false).save!

    catalog = described_class.catalog

    expect(catalog.map { |c| c[:key] }).to eq(%w[rapidos vip])
    expect(catalog.first[:items].map(&:name)).to eq(%w[Rosa])
    expect(catalog.first[:title]).to eq("Mimos rápidos")
  end
end
