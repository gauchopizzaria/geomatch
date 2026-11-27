# Saques da carteira (Mimos) — /admin/saques.
#
# Fluxo: o usuário pede o saque (fica "Aguardando") → o admin APROVA → o
# ProcessWithdrawalJob envia o Pix:
#   - modo automático (PIX_PAYOUT_PROVIDER=mercado_pago ligado): o Mercado Pago envia e,
#     quando confirma, o saque é dado como pago sozinho (CheckPendingPayoutsJob, ou o
#     botão "Atualizar status");
#   - modo manual (padrão): o admin envia o Pix pelo app do Mercado Pago para a chave
#     mostrada aqui e clica "Marcar como pago".
# Recusar devolve o valor ao saldo do usuário. "Tentar de novo" só para envio que falhou.
class Admin::WithdrawalsController < Admin::BaseController
  STATUS_TABS = {
    "pending"  => "Aguardando aprovação",
    "approved" => "Aprovados",
    "paid"     => "Pagos",
    "rejected" => "Recusados"
  }.freeze

  before_action :set_withdrawal, except: :index

  def index
    @status      = STATUS_TABS.key?(params[:status]) ? params[:status] : "pending"
    @withdrawals = WithdrawalRequest.where(status: @status).includes(:user, :processed_by)
                                    .order(created_at: (@status == "pending" ? :asc : :desc)).limit(100)
    @counts      = WithdrawalRequest.group(:status).count
    @payout_mode = payout_mode
  end

  def approve
    WithdrawalService.approve!(@withdrawal, admin: current_user)
    redirect_back_to_list notice: automatic? ? "Saque aprovado. O Pix está sendo enviado pelo Mercado Pago." :
                                               "Saque aprovado. Envie o Pix para a chave do usuário e depois clique em Marcar como pago."
  end

  def reject
    WithdrawalService.reject!(@withdrawal, admin: current_user, reason: params[:reason].presence)
    redirect_back_to_list notice: "Saque recusado. #{@withdrawal.amount.format} voltaram para o saldo do usuário."
  end

  # Modo manual: o admin já enviou o Pix por fora
  def mark_paid
    if @withdrawal.payout_external_id.present? && @withdrawal.payout_status != "failed"
      return redirect_back_to_list alert: "Este Pix está com o Mercado Pago. Use Atualizar status — ele dá baixa sozinho quando confirmar."
    end

    WithdrawalService.mark_paid!(@withdrawal, admin: current_user)
    redirect_back_to_list notice: "Saque marcado como pago."
  end

  # Modo automático: pergunta ao Mercado Pago agora (sem esperar os 10 minutos)
  def refresh
    result = PixPayoutService.call(@withdrawal)
    if result.succeeded? && @withdrawal.reload.approved?
      WithdrawalService.mark_paid!(@withdrawal, admin: current_user)
      redirect_back_to_list notice: "O Mercado Pago confirmou: Pix enviado. Saque marcado como pago."
    elsif result.failed?
      redirect_back_to_list alert: "O envio falhou: #{result.error}"
    else
      redirect_back_to_list notice: "O Mercado Pago ainda está processando este Pix."
    end
  end

  def retry_payout
    PixPayoutService.retry!(@withdrawal)
    redirect_back_to_list notice: "Novo envio do Pix iniciado."
  end

  private

  def set_withdrawal
    @withdrawal = WithdrawalRequest.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_withdrawals_path, alert: "Saque não encontrado."
  end

  def redirect_back_to_list(flash_options)
    redirect_to admin_withdrawals_path(status: params[:tab].presence || @withdrawal&.status), **flash_options
  end

  def automatic?
    payout_mode == :automatic
  end

  def payout_mode
    adapter = PixPayoutService.adapter
    return :manual unless adapter.enabled?

    adapter.respond_to?(:test_mode?) && adapter.test_mode? ? :test : :automatic
  rescue PixPayoutService::ConfigurationError
    :misconfigured
  end

  # Erros de regra (estado mudou, retry inválido) voltam como aviso na lista
  rescue_from WithdrawalService::InvalidStateError, ArgumentError do |e|
    redirect_back_to_list alert: e.message.upcase_first
  end
end
