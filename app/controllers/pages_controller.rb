class PagesController < ApplicationController
  before_action :authenticate_user!, only: [
    :mimo_catalog, :mimo_custom, :mimo_confirm, :mimo_celebration, :mimo_wallet, :mimo_withdraw, :mimo_deposit
  ]

  def landing
    redirect_to discover_3d_path if user_signed_in?
    @hide_layout_footer = true
  end

  def terms
  end

  def privacy
  end

  def suporte
  end

  # Guia de instalação do app iOS via TestFlight (beta)
  def testflight_guide
    @hide_layout_footer = true
    @seo_tags[:title]       = "Como instalar o GeoMatch no iPhone — TestFlight"
    @seo_tags[:description] = "Passo a passo para instalar a versão beta do GeoMatch no iPhone usando o TestFlight, o app oficial de betas da Apple."
  end

  # =========================================================
  # MIMOS (presentes virtuais) — views HTML/Stimulus que consomem os endpoints
  # JSON de MimosController/WalletsController (Fase 3) via fetch().
  # =========================================================

  # "Enviar um Mimo": catálogo por categoria (Rápidos, Bebidas…), cada mimo com Simples,
  # Especial e Premium. Tudo vem desenhado do servidor; mimo_send_controller.js cuida da
  # seleção, da folha "escolha o tamanho", da tela de informações e do envio.
  def mimo_catalog
    @hide_sidebar = true
    @receiver     = User.find_by(id: params[:receiver_id])
    @catalog      = MimoItem.catalog
    @balance      = current_user.wallet&.available_balance_cents.to_i
    @back_path    = mimo_back_path
  end

  # "Mimo do seu jeito": quem envia digita o que quer dar e o valor (R$ 5 a R$ 500).
  def mimo_custom
    @hide_sidebar = true
    @receiver     = User.find_by(id: params[:receiver_id])
    @balance      = current_user.wallet&.available_balance_cents.to_i
    @back_path    = safe_return_path(params[:voltar]) || mimo_catalog_page_path(receiver_id: @receiver&.id)
    # Para onde ir depois de enviar: a tela que abriu o catálogo (conversa, perfil)
    @done_path    = safe_return_path(params[:depois]) || (@receiver ? user_path(@receiver) : matches_path)
  end

  # A tela de confirmação antiga virou a folha "escolha o tamanho" do catálogo.
  # Links antigos continuam funcionando: voltam para o catálogo da mesma pessoa.
  def mimo_confirm
    redirect_to mimo_catalog_page_path(receiver_id: params[:receiver_id].presence)
  end

  # "Você ganhou um mimo" — aberta pela notificação/push e pelo extrato da carteira.
  # Mostra o emoji do mimo (ou a caixa de presente no Mimo do seu jeito), quanto entrou
  # na carteira e os botões Agradecer / Ver perfil.
  def mimo_celebration
    @hide_sidebar     = true
    @mimo_transaction = MimoTransaction.includes(:sender, :mimo_item).find(params[:id])

    unless @mimo_transaction.receiver_id == current_user.id
      redirect_to mimo_wallet_page_path, alert: "Este Mimo não pertence a você." and return
    end
    # Pagamento ainda não aprovado (ou estornado): o valor não está na carteira
    unless @mimo_transaction.completed?
      redirect_to mimo_wallet_page_path, alert: "Este mimo ainda não está disponível." and return
    end

    @sender       = @mimo_transaction.sender
    @conversation = Match.for_user(current_user.id)
                         .where("user_id = :id OR matched_user_id = :id", id: @sender.id).first
  rescue ActiveRecord::RecordNotFound
    redirect_to mimo_wallet_page_path, alert: "Mimo não encontrado."
  end

  # Carteira digital — saldo e extrato carregados via /wallet e /wallet/transactions.
  # Carteira: o saldo já vem desenhado (sem piscar "R$ 0,00"); o wallet_controller.js
  # concilia depósitos pendentes, atualiza o saldo e carrega o histórico.
  def mimo_wallet
    @hide_sidebar   = true
    @wallet         = current_user.wallet
    @balance_hidden = cookies[:hide_wallet_balance] == "1" # o mesmo olho de Meu Perfil
  end

  # Adicionar saldo — R$ 20 / 50 / 100 ou outro valor, envia para /wallet/deposit.
  # O saldo atual alimenta o "Saldo depois" (wallet_controller.js).
  def mimo_deposit
    @hide_sidebar = true
    @wallet       = current_user.wallet
  end

  # Saque para PIX — envia para /wallet/withdraw.
  # Sacar via Pix — disponível e chave Pix salva já vêm desenhados; envia para /wallet/withdraw.
  def mimo_withdraw
    @hide_sidebar = true
    @wallet       = current_user.wallet
  end

  private

  # De onde a pessoa abriu o catálogo (a conversa, o perfil): o "voltar" e o destino
  # depois de enviar. Só caminhos internos; as próprias telas de Mimo não contam.
  def mimo_back_path
    safe_return_path(params[:voltar]) ||
      safe_return_path(referer_path) ||
      (@receiver ? user_path(@receiver) : my_profile_path)
  end

  def referer_path
    uri = URI.parse(request.referer.to_s)
    return nil if uri.host.present? && uri.host != request.host

    [ uri.path, uri.query ].compact.join("?")
  rescue URI::InvalidURIError
    nil
  end

  def safe_return_path(path)
    path = path.to_s
    return nil unless path.start_with?("/") && !path.start_with?("//")
    return nil if path.start_with?("/mimos")

    path
  end
end
