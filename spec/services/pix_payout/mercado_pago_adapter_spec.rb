require "rails_helper"

# Envio de Pix pela API de Payouts do Mercado Pago (formato da documentação oficial:
# https://www.mercadopago.com.br/developers/pt/docs/payouts/integration-configuration/money-transfers)
RSpec.describe PixPayout::MercadoPagoAdapter do
  let(:key_pair)    { OpenSSL::PKey.generate_key("ED25519") }
  let(:private_pem) { key_pair.private_to_pem }
  let(:env) do
    {
      "PIX_PAYOUT_ENABLED" => "true",
      "MERCADO_PAGO_PAYOUT_ACCESS_TOKEN" => "APP_USR-token",
      "MERCADO_PAGO_PAYOUT_TEST" => nil,
      "MERCADO_PAGO_PAYOUT_PRIVATE_KEY" => private_pem
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    env.each { |key, value| allow(ENV).to receive(:[]).with(key).and_return(value) }
  end

  def send_pix(**overrides)
    described_class.new.send_pix(**{ amount_cents: 32_340, pix_key: "529.982.247-25", pix_key_type: "cpf",
                                     idempotency_key: "abc-1", reference: "saque_abc", description: "Saque GeoMatch #1" }.merge(overrides))
  end

  describe "#enabled?" do
    it "liga com a flag, o token e (em produção) a chave privada" do
      expect(described_class.new).to be_enabled
    end

    it "em produção sem a chave privada fica desligado (cai no envio manual)" do
      env["MERCADO_PAGO_PAYOUT_PRIVATE_KEY"] = nil
      allow(ENV).to receive(:[]).with("MERCADO_PAGO_PAYOUT_PRIVATE_KEY").and_return(nil)

      expect(described_class.new).not_to be_enabled
    end

    it "em teste não precisa da chave privada" do
      allow(ENV).to receive(:[]).with("MERCADO_PAGO_PAYOUT_PRIVATE_KEY").and_return(nil)
      allow(ENV).to receive(:[]).with("MERCADO_PAGO_PAYOUT_TEST").and_return("true")

      expect(described_class.new).to be_enabled
    end

    it "sem a flag fica desligado" do
      allow(ENV).to receive(:[]).with("PIX_PAYOUT_ENABLED").and_return(nil)

      expect(described_class.new).not_to be_enabled
    end
  end

  describe "#send_pix em produção" do
    it "manda o lote no formato do Payouts, assinado com a chave Ed25519" do
      stub = stub_request(:post, "https://api.mercadopago.com/v1/payouts")
             .to_return(status: 202, headers: { "Content-Type" => "application/json" },
                        body: { id: "POP01", status: "created", external_reference: "saque_abc" }.to_json)

      result = send_pix

      expect(result).to have_attributes(status: :pending, external_id: "POP01")
      expect(stub).to have_been_requested.once
      expect(a_request(:post, "https://api.mercadopago.com/v1/payouts").with { |req|
        body = JSON.parse(req.body)
        signature = Base64.strict_decode64(req.headers["X-Signature"])

        req.headers["Authorization"] == "Bearer APP_USR-token" &&
          req.headers["X-Idempotency-Key"] == "abc-1" &&
          req.headers["X-Enforce-Signature"] == "true" &&
          req.headers["X-Test-Token"].nil? &&
          key_pair.verify(nil, signature, req.body) && # assinatura confere com o corpo enviado
          body == {
            "external_reference" => "saque_abc",
            "description" => "Saque GeoMatch 1",
            "transactions" => [ {
              "type" => "pix",
              "description" => "Saque GeoMatch 1",
              "external_reference" => "saque_abc",
              "pix" => { "type" => "CPF", "chave" => "529.982.247-25" },
              "amount" => { "currency" => "BRL", "value" => 323.4 }
            } ]
          }
      }).to have_been_made
    end

    it "chave aleatória vai como PIX_CODE" do
      stub_request(:post, "https://api.mercadopago.com/v1/payouts").to_return(status: 202, body: { id: "POP02" }.to_json)

      send_pix(pix_key: "123e4567-e89b-12d3-a456-426614174000", pix_key_type: "random")

      expect(a_request(:post, "https://api.mercadopago.com/v1/payouts").with { |req|
        JSON.parse(req.body).dig("transactions", 0, "pix", "type") == "PIX_CODE"
      }).to have_been_made
    end

    it "recusa do Mercado Pago (4xx) vira :failed com a mensagem" do
      stub_request(:post, "https://api.mercadopago.com/v1/payouts")
        .to_return(status: 400, body: { error: "invalid_signature", message: "A assinatura é inválida" }.to_json)

      result = send_pix

      expect(result.status).to eq(:failed)
      expect(result.error).to include("400", "A assinatura é inválida")
    end

    it "sem resposta (rede) vira :failed pedindo para conferir no painel antes de reenviar" do
      stub_request(:post, "https://api.mercadopago.com/v1/payouts").to_timeout

      result = send_pix

      expect(result.status).to eq(:failed)
      expect(result.error).to include("Confira no painel do Mercado Pago")
    end
  end

  describe "#send_pix em teste" do
    it "manda X-test-token e não assina" do
      allow(ENV).to receive(:[]).with("MERCADO_PAGO_PAYOUT_TEST").and_return("true")
      stub_request(:post, "https://api.mercadopago.com/v1/payouts").to_return(status: 202, body: { id: "POP03" }.to_json)

      send_pix

      expect(a_request(:post, "https://api.mercadopago.com/v1/payouts").with { |req|
        req.headers["X-Test-Token"] == "true" && req.headers["X-Enforce-Signature"] == "false" && req.headers["X-Signature"].nil?
      }).to have_been_made
    end
  end

  describe "#fetch_status (resultado da transação)" do
    def stub_transactions(*transactions)
      stub_request(:get, "https://api.mercadopago.com/v1/payouts/POP01/transactions?limit=10")
        .to_return(status: 200, body: { results: transactions }.to_json)
    end

    it "success + accredited → :succeeded (pode dar baixa)" do
      stub_transactions({ id: "TOP1", status: "success", status_detail: "accredited" })

      expect(described_class.new.fetch_status("POP01")).to have_attributes(status: :succeeded, external_id: "POP01")
    end

    it "success + in_progress continua :pending" do
      stub_transactions({ id: "TOP1", status: "success", status_detail: "in_progress" })

      expect(described_class.new.fetch_status("POP01").status).to eq(:pending)
    end

    it "rejected / error → :failed com o motivo" do
      stub_transactions({ id: "TOP1", status: "error", status_detail: "invalid_chave_pix" })

      result = described_class.new.fetch_status("POP01")
      expect(result.status).to eq(:failed)
      expect(result.error).to include("invalid_chave_pix")
    end

    it "sem transação ainda → :pending" do
      stub_transactions

      expect(described_class.new.fetch_status("POP01").status).to eq(:pending)
    end
  end
end
