require "rails_helper"

# /admin/saques — aprovar, recusar, dar baixa e reenviar o Pix dos saques
RSpec.describe "Admin · Saques", type: :request do
  let(:admin) { create(:user, admin: true, onboarding_completed: true) }
  let(:user)  { create(:user, username: "Maria Clara", onboarding_completed: true) }
  let(:cpf)   { "529.982.247-25" }

  def withdrawal(amount_cents: 35_000)
    user.create_wallet!(balance_cents: amount_cents, pix_key: cpf, pix_key_type: "cpf")
    WithdrawalService.request!(user: user, amount_cents: amount_cents)
  end

  before do
    allow(MpTransferService).to receive(:call)
    sign_in admin, scope: :user
  end

  it "só admin entra" do
    sign_in user, scope: :user

    get "/admin/saques"

    expect(response).to redirect_to(root_path)
  end

  it "lista os pedidos aguardando com valor, chave Pix e o modo manual" do
    wr = withdrawal

    get "/admin/saques"
    page = Nokogiri::HTML(response.body)

    row = page.at_css("#saque-#{wr.id}")
    expect(row.text).to include("Maria Clara", "R$ 350,00", cpf)
    expect(row.at_css("form[action^='/admin/saques/#{wr.id}/approve'] button").text).to eq("Aprovar")
    expect(page.text).to include("Envio manual")
  end

  it "aprovar enfileira o envio do Pix" do
    wr = withdrawal

    expect { patch "/admin/saques/#{wr.id}/approve" }.to have_enqueued_job(ProcessWithdrawalJob).with(wr.id)

    expect(wr.reload).to be_approved
    expect(wr.processed_by).to eq(admin)
    expect(response).to redirect_to("/admin/saques?status=approved")
  end

  it "recusar devolve o valor ao saldo e guarda o motivo" do
    wr = withdrawal

    patch "/admin/saques/#{wr.id}/reject", params: { reason: "Chave de outra pessoa" }

    expect(wr.reload).to be_rejected
    expect(wr.admin_notes).to eq("Chave de outra pessoa")
    expect(user.wallet.reload.available_balance_cents).to eq(35_000)
  end

  it "modo manual: marcar como pago dá baixa no saldo" do
    wr = withdrawal
    WithdrawalService.approve!(wr, admin: admin)

    patch "/admin/saques/#{wr.id}/mark_paid"

    expect(wr.reload).to be_paid
    expect(user.wallet.reload).to have_attributes(balance_cents: 0, pending_withdrawal_cents: 0)
  end

  it "Pix com o Mercado Pago em andamento: não deixa marcar como pago na mão" do
    wr = withdrawal
    WithdrawalService.approve!(wr, admin: admin)
    wr.update!(payout_external_id: "POP01", payout_status: "pending")

    patch "/admin/saques/#{wr.id}/mark_paid"

    expect(wr.reload).to be_approved
    expect(flash[:alert]).to include("Atualizar status")
  end

  it "Atualizar status: quando o Mercado Pago confirma, dá baixa" do
    wr = withdrawal
    WithdrawalService.approve!(wr, admin: admin)
    wr.update!(payout_external_id: "POP01", payout_status: "pending", payout_provider: "mercado_pago")
    adapter = instance_double(PixPayout::MercadoPagoAdapter, name: "mercado_pago", enabled?: true)
    allow(PixPayoutService).to receive(:adapter).and_return(adapter)
    allow(adapter).to receive(:fetch_status).and_return(PixPayoutService::Result.new(status: :succeeded, external_id: "POP01"))

    patch "/admin/saques/#{wr.id}/refresh"

    expect(wr.reload).to be_paid
    expect(flash[:notice]).to include("Pix enviado")
  end

  it "Tentar de novo: só para envio que falhou" do
    wr = withdrawal
    WithdrawalService.approve!(wr, admin: admin)
    wr.update!(payout_status: "failed", payout_error: "invalid_chave_pix")

    expect { patch "/admin/saques/#{wr.id}/retry_payout" }
      .to have_enqueued_job(ProcessWithdrawalJob).with(wr.id, retry_payout: true)

    wr.update!(payout_status: "pending", payout_external_id: "POP02")
    patch "/admin/saques/#{wr.id}/retry_payout"
    expect(flash[:alert]).to be_present
  end

  it "o menu do admin mostra quantos saques aguardam" do
    withdrawal

    get "/admin/saques"

    link = Nokogiri::HTML(response.body).at_css("aside a[href='/admin/saques']")
    expect(link.text.squish).to eq("Saques 1")
  end
end
