require "rails_helper"

# "Uma pequena parte (12%) cobre os custos do serviço": quem recebe fica com 88%,
# pague quem enviou com o saldo ou com Pix/cartão.
RSpec.describe MimoFeeCalculator do
  it "R$ 100,00 viram R$ 88,00 para quem recebe (como na tela)" do
    expect(described_class.call(10_000).receiver_value_cents).to eq(8_800)
    expect(described_class.call(10_000, apply_mp_fee: false).receiver_value_cents).to eq(8_800)
  end

  it "pelo Mercado Pago, a taxa do MP sai de dentro dos 12%" do
    breakdown = described_class.call(10_000)

    expect(breakdown.to_h).to eq(gross_cents: 10_000, mp_fee_cents: 499, platform_fee_cents: 701, receiver_value_cents: 8_800)
  end

  it "com o saldo da carteira não há taxa do MP: os 12% ficam com a plataforma" do
    breakdown = described_class.call(10_000, apply_mp_fee: false)

    expect(breakdown.to_h).to eq(gross_cents: 10_000, mp_fee_cents: 0, platform_fee_cents: 1_200, receiver_value_cents: 8_800)
  end

  it "arredonda para o centavo mais próximo e as partes sempre somam o total" do
    [ 190, 290, 490, 1_999, 999_990 ].each do |gross|
      breakdown = described_class.call(gross)

      expect(breakdown.mp_fee_cents + breakdown.platform_fee_cents + breakdown.receiver_value_cents).to eq(gross)
      expect(breakdown.platform_fee_cents).to be >= 0
    end
    expect(described_class.receiver_value_cents(190)).to eq(167) # R$ 1,90 − 12% (0,228 → 0,23)
  end

  it "recusa valor zero ou negativo" do
    expect { described_class.call(0) }.to raise_error(ArgumentError)
  end
end
