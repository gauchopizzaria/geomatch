require "rails_helper"

# Regras da tela "Como funcionam os Mimos?": saque a partir de R$ 300, via Pix, para uma
# chave no próprio CPF; mimo recebido só pode ser sacado 2 dias depois.
RSpec.describe WithdrawalService do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:cpf)  { "529.982.247-25" } # CPF válido (dígitos verificadores certos)

  describe "valor mínimo de saque" do
    it "é R$ 300,00" do
      expect(described_class::MINIMUM_AMOUNT_CENTS).to eq(30_000)
    end

    it "aceita um saque de exatamente R$ 300,00" do
      user.create_wallet!(balance_cents: 30_000, pix_key: cpf, pix_key_type: "cpf")

      request = described_class.request!(user: user, amount_cents: 30_000)

      expect(request).to be_persisted
      expect(request.amount_cents).to eq(30_000)
      expect(user.reload.wallet.pending_withdrawal_cents).to eq(30_000)
    end

    it "recusa abaixo do mínimo" do
      user.create_wallet!(balance_cents: 100_000, pix_key: cpf, pix_key_type: "cpf")

      expect { described_class.request!(user: user, amount_cents: 29_999) }
        .to raise_error(described_class::MinimumAmountError, /R\$ 300,00/)
    end
  end

  describe "chave Pix no CPF" do
    before { user.create_wallet!(balance_cents: 50_000) }

    it "recusa chave de outro tipo" do
      expect { described_class.request!(user: user, amount_cents: 30_000, pix_key: "eu@email.com", pix_key_type: "email") }
        .to raise_error(described_class::MissingPixKeyError, /CPF/)
    end

    it "recusa CPF com dígitos verificadores errados" do
      expect { described_class.request!(user: user, amount_cents: 30_000, pix_key: "529.982.247-26", pix_key_type: "cpf") }
        .to raise_error(described_class::MissingPixKeyError, /CPF/)
    end

    it "aceita CPF com ou sem pontuação" do
      request = described_class.request!(user: user, amount_cents: 30_000, pix_key: "52998224725", pix_key_type: "cpf")

      expect(request).to have_attributes(pix_key: "52998224725", pix_key_type: "cpf")
    end

    it "valida os dígitos do CPF" do
      expect(described_class.valid_cpf?("529.982.247-25")).to be(true)
      expect(described_class.valid_cpf?("111.111.111-11")).to be(false)
      expect(described_class.valid_cpf?("123")).to be(false)
    end
  end

  describe "mimo recebido só pode ser sacado 2 dias depois" do
    let(:sender) { create(:user) }
    let(:item) do
      MimoItem.create!(name: "Coroa", icon: "👑", category: "vip", active: true, price_cents: 99_990, receiver_value_cents: 0,
                       tiers: MimoItem::TIER_KEYS.map { |key| { "key" => key, "label" => key, "price_cents" => 40_000 } })
    end

    before do
      allow(MimoNotificationService).to receive(:call)
      user.create_wallet!(balance_cents: 30_000, pix_key: cpf, pix_key_type: "cpf")
      sender.create_wallet!(balance_cents: 40_000)
      MimoWalletPaymentService.call(sender: sender, receiver: user, selection: MimoSelection.from_item(item, "simples"))
    end

    it "o valor do mimo recebido hoje fica de fora do que dá para sacar" do
      wallet = user.reload.wallet

      expect(wallet.balance_cents).to eq(65_200)         # 300 + 352 (88% de 400)
      expect(wallet.on_hold_cents).to eq(35_200)
      expect(wallet.withdrawable_cents).to eq(30_000)
      expect { described_class.request!(user: user, amount_cents: 40_000) }
        .to raise_error(described_class::InsufficientBalanceError, /2 dias/)
    end

    it "depois de 2 dias, libera" do
      travel 2.days + 1.minute do
        request = described_class.request!(user: user, amount_cents: 65_200)

        expect(request.amount_cents).to eq(65_200)
      end
    end
  end

  describe "regras que continuam valendo" do
    before { user.create_wallet!(balance_cents: 60_000, pix_key: cpf, pix_key_type: "cpf") }

    it "recusa saque maior que o saldo disponível" do
      expect { described_class.request!(user: user, amount_cents: 70_000) }
        .to raise_error(described_class::InsufficientBalanceError)
    end

    it "recusa um segundo saque dentro de 24h" do
      described_class.request!(user: user, amount_cents: 30_000)

      expect { described_class.request!(user: user, amount_cents: 30_000) }
        .to raise_error(described_class::RateLimitedError)
    end

    it "exige chave PIX cadastrada" do
      user.wallet.update!(pix_key: nil, pix_key_type: nil)

      expect { described_class.request!(user: user, amount_cents: 30_000) }
        .to raise_error(described_class::MissingPixKeyError)
    end
  end
end
