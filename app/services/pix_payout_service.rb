# Envio automático do PIX de saque para a chave do usuário.
#
# Até aqui o sistema só movia dinheiro ENTRE as contas da plataforma
# (MpTransferService, Bolsão -> Operacional) e o envio final era manual. Este
# serviço fecha essa lacuna, mas de propósito NÃO fala com nenhum provedor
# diretamente: ele escolhe um adaptador via ENV["PIX_PAYOUT_PROVIDER"].
#
# Provedores: `manual` (padrão — o operador envia o PIX na mão e dá baixa em
# /admin/saques) e `mercado_pago` (API de Payouts, ver PixPayout::MercadoPagoAdapter).
# Trocar de um para o outro é trocar variáveis de ambiente.
#
# REGRA INEGOCIÁVEL — idempotência: dinheiro enviado não volta. Uma ordem só é
# criada no provedor se `payout_external_id` ainda estiver vazio, e a coluna tem
# índice único. Qualquer retry automático (job, deploy no meio da execução, admin
# clicando duas vezes) consulta o status em vez de reenviar.
#
# Reenviar de propósito só pelo PixPayoutService.retry! (botão "Tentar de novo" em
# /admin/saques), e só depois de o envio anterior ter FALHADO. A chave de
# idempotência é "id do saque + número da tentativa": a mesma tentativa repetida
# nunca vira dois Pix; uma tentativa nova (depois de uma falha confirmada) tem
# chave nova.
class PixPayoutService
  class ConfigurationError < StandardError; end

  # status:
  #   :succeeded — provedor confirmou que o PIX saiu -> pode dar baixa (mark_paid!)
  #   :pending   — provedor aceitou e ainda processa -> NÃO dar baixa ainda
  #   :failed    — não saiu; o valor continua reservado para nova tentativa
  #   :skipped   — nenhum provedor automático configurado (envio manual)
  Result = Struct.new(:status, :external_id, :raw, :error, keyword_init: true) do
    def succeeded? = status == :succeeded
    def pending?   = status == :pending
    def failed?    = status == :failed
    def skipped?   = status == :skipped
  end

  ADAPTERS = {
    "manual"       => "PixPayout::ManualAdapter",
    "mercado_pago" => "PixPayout::MercadoPagoAdapter"
  }.freeze

  DEFAULT_PROVIDER = "manual".freeze

  def self.call(withdrawal_request)
    new(withdrawal_request).call
  end

  # "Tentar de novo" (admin): só para saque aprovado cujo envio falhou. Abre uma
  # tentativa nova (chave de idempotência nova) e manda o ProcessWithdrawalJob enviar,
  # sem repetir a movimentação entre as contas da plataforma.
  def self.retry!(withdrawal_request)
    unless withdrawal_request.approved? && withdrawal_request.payout_status == "failed"
      raise ArgumentError, "só dá para tentar de novo um saque aprovado cujo envio falhou"
    end

    payload  = (withdrawal_request.payout_payload || {}).to_h
    previous = Array(payload["previous_payout_ids"]) + [ withdrawal_request.payout_external_id ].compact
    withdrawal_request.update!(
      payout_external_id: nil,
      payout_status: "retry",
      payout_error: nil,
      payout_payload: { "attempt" => attempt_of(withdrawal_request) + 1, "previous_payout_ids" => previous }
    )
    ProcessWithdrawalJob.perform_later(withdrawal_request.id, retry_payout: true)
  end

  def self.attempt_of(withdrawal_request)
    (withdrawal_request.payout_payload || {}).to_h.fetch("attempt", 1).to_i
  end

  # Identificador do saque no provedor: até 50 caracteres, só letras, números e _
  def self.reference_for(withdrawal_request)
    "saque_#{withdrawal_request.id.to_s.delete('-')}"
  end

  def self.adapter
    key = ENV["PIX_PAYOUT_PROVIDER"].presence || DEFAULT_PROVIDER
    class_name = ADAPTERS[key] ||
                 raise(ConfigurationError, "PIX_PAYOUT_PROVIDER=#{key.inspect} desconhecido — use um de: #{ADAPTERS.keys.join(', ')}")

    class_name.constantize.new
  end

  def initialize(withdrawal_request)
    @withdrawal_request = withdrawal_request
  end

  def call
    return already_requested if withdrawal_request.payout_external_id.present?

    adapter = self.class.adapter
    return skipped(adapter) unless adapter.enabled?

    withdrawal_request.update!(
      payout_provider: adapter.name,
      payout_status: "requested",
      payout_requested_at: Time.current,
      payout_error: nil
    )

    attempt = self.class.attempt_of(withdrawal_request)
    result = adapter.send_pix(
      amount_cents: withdrawal_request.amount_cents,
      pix_key: withdrawal_request.pix_key,
      pix_key_type: withdrawal_request.pix_key_type,
      # "id do saque + tentativa": estável se o envio se repetir (a resposta se perdeu,
      # o job rodou de novo) — o provedor devolve a MESMA ordem em vez de pagar em dobro
      idempotency_key: "#{withdrawal_request.id}-#{attempt}",
      reference: self.class.reference_for(withdrawal_request),
      description: "Saque GeoMatch"
    )

    persist!(result)
    result
  rescue StandardError => e
    Rails.logger.error "[PixPayoutService] Falha ao enviar PIX do saque #{withdrawal_request.id}: #{e.class}: #{e.message}"
    failure = Result.new(status: :failed, error: "#{e.class}: #{e.message}")
    persist!(failure)
    failure
  end

  private

  attr_reader :withdrawal_request

  # Ordem já criada no provedor: nunca reenvia. Se o adaptador souber consultar,
  # pergunta o status atual; senão trata como ainda em processamento.
  def already_requested
    adapter = self.class.adapter

    result =
      if adapter.respond_to?(:fetch_status)
        adapter.fetch_status(withdrawal_request.payout_external_id)
      else
        Result.new(status: :pending, external_id: withdrawal_request.payout_external_id)
      end

    persist!(result)
    result
  rescue StandardError => e
    Rails.logger.error "[PixPayoutService] Falha ao consultar payout #{withdrawal_request.payout_external_id}: #{e.class}: #{e.message}"
    Result.new(status: :pending, external_id: withdrawal_request.payout_external_id)
  end

  def skipped(adapter)
    Rails.logger.info "[PixPayoutService] Provedor #{adapter.name.inspect} não envia PIX automaticamente — " \
                      "saque #{withdrawal_request.id} aguarda envio manual."
    withdrawal_request.update!(payout_provider: adapter.name, payout_status: "manual")
    Result.new(status: :skipped)
  end

  # Guarda a resposta do provedor sem perder o número da tentativa nem as ordens
  # anteriores (que o retry! precisa)
  def persist!(result)
    kept = (withdrawal_request.payout_payload || {}).to_h.slice("attempt", "previous_payout_ids")
    withdrawal_request.update!(
      payout_status: result.status.to_s,
      payout_external_id: result.external_id.presence || withdrawal_request.payout_external_id,
      payout_error: result.error,
      payout_payload: kept.merge("response" => result.raw).compact
    )
  end
end
