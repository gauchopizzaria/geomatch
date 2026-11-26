# Endpoints JSON de Mimos (presentes virtuais), usados pela tela "Enviar um Mimo"
# (mimo_send_controller.js) e pelo app mobile.
#
# O que pode ser enviado (ver MimoSelection):
#   - catálogo: mimo_item_id + tier ("simples" | "especial" | "premium"; sem tier,
#     o app antigo continua pagando o preço do próprio item);
#   - "Mimo do seu jeito": custom_label + amount_cents (R$ 5,00 a R$ 500,00).
class MimosController < ApplicationController
  include AuthenticatesForMobile

  # ApplicationController não registra authenticate_user! globalmente (cada
  # controller declara o seu) — nada a pular aqui, só o before_action próprio.
  skip_before_action :verify_authenticity_token, only: [ :create, :send_with_wallet ]
  before_action :authenticate_for_mobile!

  # GET /mimo_items/catalog
  def catalog
    items = MimoItem.active.ordered

    render json: {
      items: items.map { |item| catalog_item_json(item) },
      categories: MimoItem::CATEGORIES
    }
  end

  # POST /mimo/enviar — o botão "Enviar …" da tela nova.
  # Com saldo suficiente, paga com o saldo da carteira (instantâneo); sem saldo, abre o
  # checkout do Mercado Pago (Pix ou cartão) com o mesmo valor. Convite por telefone
  # (sem conta) sempre vai pelo Mercado Pago.
  def deliver
    selection = build_selection
    message   = MimoSelection.clean_message(params[:message])
    receiver  = receiver_user
    phone     = params[:phone].presence

    if receiver && enough_balance?(selection)
      begin
        mimo_transaction = MimoWalletPaymentService.call(
          sender: mobile_current_user, receiver: receiver, selection: selection, message: message
        )
        flash[:notice] = "Mimo enviado para #{first_name(receiver)}! 🎁"
        return render json: { status: "sent", mimo_transaction_id: mimo_transaction.id }, status: :created
      rescue MimoWalletPaymentService::InsufficientBalanceError
        # O saldo mudou entre a conta e o débito: segue pelo checkout
      end
    end

    payment = MimoPaymentService.call(
      sender: mobile_current_user, receiver: receiver, receiver_phone: (receiver ? nil : phone),
      selection: selection, message: message
    )
    render json: {
      status: "checkout",
      checkout_url: payment.mercado_pago_checkout_url,
      mimo_transaction_id: payment.mimo_transaction.id
    }, status: :created
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Mimo ou pessoa não encontrados." }, status: :not_found
  rescue MimoSelection::InvalidError,
         MimoPaymentService::InvalidRecipientError, MimoPaymentService::ItemUnavailableError,
         MimoWalletPaymentService::InvalidRecipientError, MimoWalletPaymentService::ItemUnavailableError => e
    render json: { error: e.message.upcase_first }, status: :unprocessable_entity
  rescue MimoPaymentService::ConfigurationError, MimoPaymentService::ProviderError => e
    Rails.logger.error "[MimosController#deliver] Falha de integração MP: #{e.class}: #{e.message}"
    render json: { error: "Seu saldo não cobre este mimo e o pagamento por Pix/cartão não abriu agora. Adicione saldo ou tente de novo." },
           status: :bad_request
  end

  # POST /mimo/send
  # Params: (mimo_item_id [+ tier] | custom_label + amount_cents) + exatamente um de:
  #         receiver_id | phone; message (opcional)
  def create
    payment = MimoPaymentService.call(
      sender:         mobile_current_user,
      receiver:       receiver_user,
      receiver_phone: params[:phone].presence,
      selection:      build_selection,
      message:        MimoSelection.clean_message(params[:message])
    )

    mimo_transaction = payment.mimo_transaction
    render json: {
      payment_id: payment.id,
      mimo_transaction_id: mimo_transaction.id,
      checkout_url: payment.mercado_pago_checkout_url,
      status: mimo_transaction.status
    }, status: :created
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue MimoSelection::InvalidError, MimoPaymentService::InvalidRecipientError, MimoPaymentService::ItemUnavailableError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue MimoPaymentService::ConfigurationError, MimoPaymentService::ProviderError => e
    Rails.logger.error "[MimosController] Falha de integração MP: #{e.class}: #{e.message}"
    render json: { error: "Não foi possível iniciar o pagamento no momento." }, status: :bad_request
  end

  # POST /mimo/send_with_wallet
  # Params: (mimo_item_id [+ tier] | custom_label + amount_cents) + receiver_id
  #         (obrigatório — sem convite por telefone aqui: não há saldo a creditar em
  #         quem ainda não tem carteira). message (opcional). Transferência interna
  #         síncrona, sem Mercado Pago.
  def send_with_wallet
    receiver = receiver_user
    raise ActionController::ParameterMissing, :receiver_id if receiver.nil?

    mimo_transaction = MimoWalletPaymentService.call(
      sender: mobile_current_user,
      receiver: receiver,
      selection: build_selection,
      message: MimoSelection.clean_message(params[:message])
    )

    render json: {
      mimo_transaction_id: mimo_transaction.id,
      status: mimo_transaction.status
    }, status: :created
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue MimoSelection::InvalidError,
         MimoWalletPaymentService::InsufficientBalanceError,
         MimoWalletPaymentService::InvalidRecipientError,
         MimoWalletPaymentService::ItemUnavailableError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def receiver_user
    return nil if params[:receiver_id].blank?

    User.find(params[:receiver_id])
  end

  # Catálogo (mimo_item_id + tier) ou "Mimo do seu jeito" (custom_label + amount_cents).
  # Preço e nome sempre saem do servidor — nunca do que o navegador mandou como preço.
  def build_selection
    if params[:mimo_item_id].present?
      MimoSelection.from_item(MimoItem.active.find(params[:mimo_item_id]), params[:tier])
    elsif params.key?(:custom_label) || params.key?(:amount_cents)
      MimoSelection.custom(label: params[:custom_label], amount_cents: params[:amount_cents])
    else
      raise ActionController::ParameterMissing, :mimo_item_id
    end
  end

  def enough_balance?(selection)
    wallet = mobile_current_user.wallet
    wallet.present? && wallet.available_balance_cents >= selection.price_cents
  end

  def first_name(user)
    user.display_name.to_s.split.first.presence || "a pessoa"
  end

  def catalog_item_json(item)
    {
      id: item.id,
      name: item.name,
      description: item.description,
      icon: item.icon,
      category: item.category,
      price_cents: item.price_cents,
      price_formatted: item.price.format,
      starting_price_cents: item.starting_price_cents,
      tiers: item.tier_list.map { |tier| tier.merge(price_formatted: Money.new(tier[:price_cents], "BRL").format) },
      position: item.position
    }
  end
end
