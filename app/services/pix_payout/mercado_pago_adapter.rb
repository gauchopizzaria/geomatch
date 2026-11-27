module PixPayout
  # Envio de Pix para a chave do usuário pela API de Payouts do Mercado Pago.
  # Documentação: https://www.mercadopago.com.br/developers/pt/docs/payouts/overview
  #
  # COMO LIGAR (passo a passo completo na mensagem do commit / guia de saques):
  #   PIX_PAYOUT_PROVIDER=mercado_pago
  #   PIX_PAYOUT_ENABLED=true
  #   MERCADO_PAGO_PAYOUT_ACCESS_TOKEN=APP_USR-...  (Access Token da aplicação com Payouts;
  #                                                   sem ele, usa MERCADO_PAGO_ACCESS_TOKEN)
  #   Teste:     MERCADO_PAGO_PAYOUT_TEST=true  (token de teste; nenhum dinheiro de verdade)
  #   Produção:  MERCADO_PAGO_PAYOUT_PRIVATE_KEY=<conteúdo do mpprivate.pem>
  #              (chave Ed25519; a pública correspondente é cadastrada pelo Mercado Pago)
  #
  # Faltando qualquer peça (flag, token ou — em produção — a chave privada), enabled? é
  # false e o saque cai no envio manual, em vez de quebrar no meio.
  #
  # Como o Mercado Pago responde:
  #   POST /v1/payouts → 202 "aceito para processamento" (ainda não diz se o Pix saiu).
  #   O resultado de verdade é o da TRANSAÇÃO: GET /v1/payouts/:id/transactions
  #     success + accredited → creditado na conta de destino   → :succeeded (dá baixa)
  #     error / rejected / canceled / refunded                 → :failed (valor segue reservado)
  #     qualquer outro (created, approved, processed, in_progress…) → :pending
  #   CheckPendingPayoutsJob consulta os :pending a cada 10 minutos.
  class MercadoPagoAdapter
    API_BASE_URL = "https://api.mercadopago.com".freeze
    ENDPOINT     = "/v1/payouts".freeze

    # Tipos de chave Pix como o Payouts nomeia (chave aleatória = PIX_CODE)
    PIX_KEY_TYPES = {
      "cpf"    => "CPF",
      "cnpj"   => "CNPJ",
      "email"  => "EMAIL",
      "phone"  => "PHONE",
      "random" => "PIX_CODE"
    }.freeze

    SUCCEEDED = [ %w[success accredited] ].freeze
    FAILED    = %w[error rejected canceled cancelled refunded failed].freeze

    def name = "mercado_pago"

    def enabled?
      ActiveModel::Type::Boolean.new.cast(ENV["PIX_PAYOUT_ENABLED"]).present? &&
        access_token.present? &&
        (test_mode? || private_key.present?)
    end

    def test_mode?
      ActiveModel::Type::Boolean.new.cast(ENV["MERCADO_PAGO_PAYOUT_TEST"]).present?
    end

    # reference: identificador do saque (até 50 caracteres; letras, números, - e _)
    def send_pix(amount_cents:, pix_key:, pix_key_type:, idempotency_key:, reference:, description: nil)
      body = JSON.generate(build_payload(amount_cents:, pix_key:, pix_key_type:, reference:, description:))

      response = connection.post(ENDPOINT) do |req|
        # Mesma chave = mesma ordem: se a resposta se perder e o envio repetir, o MP não
        # cria um segundo Pix
        req.headers["X-Idempotency-Key"] = idempotency_key.to_s
        signature_headers(body).each { |header, value| req.headers[header] = value }
        req.body = body # assinado byte a byte: vai exatamente como foi assinado
      end

      body_json = parse(response)
      payout_id = body_json["id"]&.to_s

      unless response.success?
        return PixPayoutService::Result.new(
          status: :failed, external_id: payout_id, raw: body_json,
          error: "Mercado Pago recusou o envio (#{response.status}): #{error_text(body_json)}"
        )
      end

      # 202: aceito. Se a transação já vier na resposta, usa; senão fica :pending e o
      # status é consultado depois
      transaction = Array(body_json["transactions"]).first
      status = transaction ? classify(transaction) : :pending
      PixPayoutService::Result.new(status: status, external_id: payout_id, raw: body_json,
                                   error: (transaction_error(transaction) if status == :failed))
    rescue Faraday::Error => e
      # Falha de rede é ambígua: a ordem PODE ter sido criada no MP. Não se reenvia
      # sozinho; o admin confere no painel do Mercado Pago antes de "Tentar de novo".
      PixPayoutService::Result.new(
        status: :failed,
        error: "Sem resposta do Mercado Pago (#{e.class}). Confira no painel do Mercado Pago se o Pix saiu antes de tentar de novo."
      )
    end

    def fetch_status(payout_id)
      response = connection.get("#{ENDPOINT}/#{payout_id}/transactions") do |req|
        req.params["limit"] = 10
        req.headers["X-test-token"] = "true" if test_mode?
      end
      body_json = parse(response)

      unless response.success?
        return PixPayoutService::Result.new(status: :pending, external_id: payout_id, raw: body_json,
                                            error: "Consulta ao Mercado Pago falhou (#{response.status})")
      end

      transaction = transactions_from(body_json).first
      return PixPayoutService::Result.new(status: :pending, external_id: payout_id, raw: body_json) unless transaction

      status = classify(transaction)
      PixPayoutService::Result.new(status: status, external_id: payout_id, raw: transaction,
                                   error: (transaction_error(transaction) if status == :failed))
    rescue Faraday::Error => e
      PixPayoutService::Result.new(status: :pending, external_id: payout_id, error: e.message)
    end

    private

    def access_token
      ENV["MERCADO_PAGO_PAYOUT_ACCESS_TOKEN"].presence || ENV["MERCADO_PAGO_ACCESS_TOKEN"].presence
    end

    # Conteúdo do .pem; aceita as quebras de linha escapadas como \n (variável de ambiente
    # numa linha só), como a APNS_KEY_P8
    def private_key
      pem = ENV["MERCADO_PAGO_PAYOUT_PRIVATE_KEY"].to_s.gsub("\\n", "\n").strip
      return nil if pem.empty?

      @private_key ||= OpenSSL::PKey.read(pem)
    rescue OpenSSL::PKey::PKeyError => e
      Rails.logger.error "[PixPayout::MercadoPagoAdapter] MERCADO_PAGO_PAYOUT_PRIVATE_KEY inválida: #{e.message}"
      nil
    end

    # Teste: X-test-token. Produção: corpo assinado com a chave privada Ed25519, em Base64.
    def signature_headers(body)
      if test_mode?
        { "X-test-token" => "true", "X-enforce-signature" => "false" }
      else
        { "X-enforce-signature" => "true", "X-signature" => Base64.strict_encode64(private_key.sign(nil, body)) }
      end
    end

    def build_payload(amount_cents:, pix_key:, pix_key_type:, reference:, description:)
      text = clean_description(description)
      {
        external_reference: reference,
        description: text,
        transactions: [
          {
            type: "pix",
            description: text,
            external_reference: reference,
            pix: {
              type: PIX_KEY_TYPES.fetch(pix_key_type.to_s, pix_key_type.to_s.upcase),
              chave: pix_key.to_s.strip
            },
            amount: { currency: "BRL", value: (amount_cents / 100.0).round(2) }
          }
        ]
      }.compact
    end

    # O Payouts só aceita letras, números, hífens, underlines e espaços na descrição
    def clean_description(description)
      text = I18n.transliterate(description.to_s).gsub(/[^A-Za-z0-9 _-]/, "").squish
      text.presence
    end

    def classify(transaction)
      status = transaction["status"].to_s
      detail = transaction["status_detail"].to_s

      return :succeeded if SUCCEEDED.include?([ status, detail ])
      return :failed if FAILED.include?(status)

      :pending
    end

    def transaction_error(transaction)
      return nil unless transaction

      [ transaction["status"], transaction["status_detail"], transaction["message"] || transaction["error_message"] ]
        .compact_blank.join(" — ")
    end

    def transactions_from(body_json)
      list = body_json["results"] || body_json["transactions"] || body_json["elements"]
      list.is_a?(Array) ? list : []
    end

    def error_text(body_json)
      (body_json["message"] || body_json["error"] || body_json.to_json).to_s.truncate(400)
    end

    def parse(response)
      body = response.body
      return body if body.is_a?(Hash)

      body.present? ? JSON.parse(body) : {}
    rescue JSON::ParserError
      { "raw" => body.to_s.truncate(500) }
    end

    def connection
      Faraday.new(url: API_BASE_URL) do |f|
        f.headers["Authorization"] = "Bearer #{access_token}"
        f.headers["Content-Type"]  = "application/json"
        f.headers["Accept"]        = "application/json"
        f.options.open_timeout = 5
        f.options.timeout      = 20
        f.adapter Faraday.default_adapter
      end
    end
  end
end
