require "rails_helper"

RSpec.describe PixPayoutService do
  let(:user) { create(:user) }

  def withdrawal(amount_cents: 32_340, **attrs)
    user.wallet || user.create_wallet!(balance_cents: amount_cents, pix_key: "529.982.247-25", pix_key_type: "cpf")
    request = WithdrawalService.request!(user: user, amount_cents: amount_cents)
    request.update!(**attrs) if attrs.any?
    request
  end

  def with_provider(name, enabled: "true")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PIX_PAYOUT_PROVIDER").and_return(name)
    allow(ENV).to receive(:[]).with("PIX_PAYOUT_ENABLED").and_return(enabled)
    allow(ENV).to receive(:[]).with("MERCADO_PAGO_PAYOUT_ACCESS_TOKEN").and_return(nil)
    allow(ENV).to receive(:[]).with("MERCADO_PAGO_ACCESS_TOKEN").and_return("token")
    allow(ENV).to receive(:[]).with("MERCADO_PAGO_PAYOUT_ENDPOINT").and_return(nil)
  end

  describe "sem provedor automático (padrão)" do
    it "não envia nada e devolve :skipped" do
      request = withdrawal

      result = described_class.call(request)

      expect(result).to be_skipped
      expect(request.reload.payout_status).to eq("manual")
      expect(request.payout_external_id).to be_nil
    end
  end

  describe "provedor desconhecido" do
    it "falha alto, em vez de silenciosamente não pagar" do
      with_provider("provedor_inexistente")

      expect { described_class.adapter }.to raise_error(described_class::ConfigurationError, /desconhecido/)
    end
  end

  describe "com o adaptador do Mercado Pago" do
    let(:adapter) { instance_double(PixPayout::MercadoPagoAdapter, name: "mercado_pago", enabled?: true) }

    before do
      with_provider("mercado_pago")
      allow(PixPayout::MercadoPagoAdapter).to receive(:new).and_return(adapter)
    end

    it "envia o PIX e guarda o id da ordem" do
      request = withdrawal
      allow(adapter).to receive(:send_pix).and_return(
        described_class::Result.new(status: :succeeded, external_id: "payout-1", raw: { "status" => "approved" })
      )

      result = described_class.call(request)

      expect(result).to be_succeeded
      expect(request.reload.payout_external_id).to eq("payout-1")
      expect(request.payout_status).to eq("succeeded")
      expect(request.payout_provider).to eq("mercado_pago")
    end

    it "usa 'id do saque + tentativa' como chave de idempotência e o id como referência" do
      request = withdrawal
      allow(adapter).to receive(:send_pix).and_return(described_class::Result.new(status: :succeeded, external_id: "p1"))

      described_class.call(request)

      expect(adapter).to have_received(:send_pix).with(
        hash_including(idempotency_key: "#{request.id}-1", reference: "saque_#{request.id.delete('-')}",
                       amount_cents: 32_340, pix_key: "529.982.247-25", pix_key_type: "cpf")
      )
    end

    it "repetir a mesma tentativa (job rodou de novo sem resposta) usa a MESMA chave" do
      request = withdrawal(payout_status: "requested")
      allow(adapter).to receive(:send_pix).and_return(described_class::Result.new(status: :pending, external_id: "p1"))

      described_class.call(request)

      expect(adapter).to have_received(:send_pix).with(hash_including(idempotency_key: "#{request.id}-1"))
    end

    describe ".retry! (Tentar de novo, no admin)" do
      it "depois de uma falha, abre a tentativa 2 (chave nova), guarda a ordem antiga e reenvia sem mexer na tesouraria" do
        request = withdrawal
        request.update!(status: "approved", payout_status: "failed", payout_external_id: "payout-velho")

        expect { described_class.retry!(request) }
          .to have_enqueued_job(ProcessWithdrawalJob).with(request.id, retry_payout: true)

        request.reload
        expect(request.payout_external_id).to be_nil
        expect(request.payout_payload).to include("attempt" => 2, "previous_payout_ids" => [ "payout-velho" ])

        allow(adapter).to receive(:send_pix).and_return(described_class::Result.new(status: :pending, external_id: "payout-novo"))
        described_class.call(request)
        expect(adapter).to have_received(:send_pix).with(hash_including(idempotency_key: "#{request.id}-2"))
        expect(request.reload.payout_payload).to include("attempt" => 2, "previous_payout_ids" => [ "payout-velho" ])
      end

      it "não deixa reenviar um saque cujo envio não falhou" do
        request = withdrawal
        request.update!(status: "approved", payout_status: "pending", payout_external_id: "payout-1")

        expect { described_class.retry!(request) }.to raise_error(ArgumentError)
      end
    end

    # A regra que protege o dinheiro: ordem já criada nunca é reenviada.
    it "NÃO reenvia o PIX quando já existe uma ordem no provedor" do
      request = withdrawal(payout_external_id: "payout-1", payout_status: "pending")
      # send_pix stubado só para poder provar que NÃO foi chamado.
      allow(adapter).to receive(:send_pix)
      allow(adapter).to receive(:fetch_status).and_return(
        described_class::Result.new(status: :succeeded, external_id: "payout-1")
      )

      result = described_class.call(request)

      expect(adapter).not_to have_received(:send_pix)
      expect(adapter).to have_received(:fetch_status).with("payout-1")
      expect(result).to be_succeeded
    end

    it "guarda o erro e devolve :failed quando o provedor recusa" do
      request = withdrawal
      allow(adapter).to receive(:send_pix).and_return(
        described_class::Result.new(status: :failed, error: "saldo insuficiente na conta")
      )

      result = described_class.call(request)

      expect(result).to be_failed
      expect(request.reload.payout_error).to eq("saldo insuficiente na conta")
    end

    # Exceção inesperada não pode deixar o saque num limbo silencioso.
    it "trata exceção do adaptador como falha registrada" do
      request = withdrawal
      allow(adapter).to receive(:send_pix).and_raise(StandardError, "boom")

      result = described_class.call(request)

      expect(result).to be_failed
      expect(request.reload.payout_status).to eq("failed")
      expect(request.payout_error).to include("boom")
    end
  end
end
