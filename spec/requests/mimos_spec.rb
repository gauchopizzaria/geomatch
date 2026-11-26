require "rails_helper"

# Módulo de Mimos: catálogo com Simples/Especial/Premium, envio (saldo ou Pix/cartão),
# "Mimo do seu jeito", tela de quem recebeu e agradecimento.
RSpec.describe "Mimos", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:luan)  { create(:user, username: "Luan Victor", onboarding_completed: true) }
  let(:clara) { create(:user, username: "Maria Clara", onboarding_completed: true) }

  let!(:rosa) { tiered_item("Rosa", "🌹", "rapidos", [ "rosa", 290 ], [ "rosa vermelha", 490 ], [ "buquê de rosas", 990 ], position: 1) }
  let!(:sushi) { tiered_item("Sushi", "🍣", "comidas", [ "combinado 20 peças", 5_990 ], [ "40 peças", 9_990 ], [ "rodízio", 17_990 ], position: 2) }
  let!(:coroa) { tiered_item("Coroa", "👑", "vip", [ "coroa", 99_990 ], [ "coroa de ouro", 199_990 ], [ "coroa de diamante", 499_990 ], position: 3) }

  before do
    allow(MatchChannel).to receive(:broadcast_to)
    allow(PushNotificationJob).to receive(:perform_later)
  end

  def tiered_item(name, icon, category, simples, especial, premium, position:)
    tiers = MimoItem::TIER_KEYS.zip([ simples, especial, premium ]).map do |key, (label, cents)|
      { "key" => key, "label" => label, "price_cents" => cents }
    end
    MimoItem.create!(name: name, icon: icon, category: category, position: position, active: true,
                     tiers: tiers, price_cents: simples.last, receiver_value_cents: 0)
  end

  def give_balance(user, cents)
    (user.wallet || user.create_wallet!).update!(balance_cents: cents)
  end

  def deliver(params)
    post "/mimo/enviar", params: params, as: :json
  end

  def stub_mercado_pago_checkout
    sdk = double("Mercadopago::SDK")
    preference = double("preference")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("MERCADO_PAGO_ACCESS_TOKEN").and_return("token")
    allow(ENV).to receive(:[]).with("APP_BASE_URL").and_return("https://geomatch.test")
    allow(Mercadopago::SDK).to receive(:new).and_return(sdk)
    allow(sdk).to receive(:preference).and_return(preference)
    allow(preference).to receive(:create).and_return({ "response" => { "init_point" => "https://mp.test/checkout/1", "id" => "pref-1" } })
    preference
  end

  describe "Enviar um Mimo (/mimos/catalogo)" do
    before { sign_in luan, scope: :user }

    it "mostra para quem, o saldo, os chips e as seções na ordem do mockup" do
      give_balance(luan, 25_000)

      get "/mimos/catalogo", params: { receiver_id: clara.id }
      page = Nokogiri::HTML(response.body)

      expect(response).to have_http_status(:ok)
      expect(page.at_css(".ms-title").text).to eq("Enviar um Mimo")
      expect(page.at_css(".ms-subtitle").text.squish).to eq("para Maria Clara")
      expect(page.at_css(".ms-balance-value").text).to eq("R$ 250,00")
      expect(page.at_css(".ms-balance-add")["href"]).to eq("/mimos/depositar")
      expect(page.css(".ms-chip").map(&:text)).to eq(%w[Rápidos Comidas VIP])
      expect(page.css(".ms-section-head h2").map { |h| h.text.squish }).to eq([ "Mimos rápidos", "Comidas", "VIP VIP" ])
      expect(page.css(".ms-section-head > span").map(&:text)).to eq([ "1 mimo", "1 mimo", "1 mimo" ])
      expect(page.at_css(".ms-custom strong").text).to eq("Mimo do seu jeito")
    end

    it "cada card traz o emoji, o 'a partir de' e os três níveis" do
      get "/mimos/catalogo", params: { receiver_id: clara.id }
      card = Nokogiri::HTML(response.body).at_css(".ms-card[data-item-id='#{rosa.id}']")

      expect(card.at_css(".ms-card-icon").text).to eq("🌹")
      expect(card.at_css(".ms-card-name").text).to eq("Rosa")
      expect(card.at_css(".ms-card-price").text).to eq("a partir de R$ 2,90")
      tiers = JSON.parse(card["data-tiers"])
      expect(tiers.map { |t| [ t["name"], t["label"], t["price"] ] }).to eq([
        [ "Simples", "rosa", "R$ 2,90" ], [ "Especial", "rosa vermelha", "R$ 4,90" ], [ "Premium", "buquê de rosas", "R$ 9,90" ]
      ])
      expect(card["class"]).to include("is-selected") # o primeiro já vem marcado (barra de baixo)
    end

    it "a tela (i) mostra as regras que o sistema aplica" do
      get "/mimos/catalogo", params: { receiver_id: clara.id }
      info = Nokogiri::HTML(response.body).at_css(".ms-info")

      expect(info.at_css(".ms-title").text).to eq("Como funcionam os Mimos?")
      expect(info.css(".ms-info-list strong").map(&:text)).to eq([
        "Enviou um mimo?", "Recebeu um mimo?", "Saque", "Também dá para usar o saldo", "Transação segura"
      ])
      text = info.text.squish
      expect(text).to include("Uma pequena parte (12%) cobre os custos do serviço.")
      expect(text).to include("fica disponível para saque 2 dias após o recebimento.")
      expect(text).to include("A partir de R$ 300, via Pix, para uma chave no seu próprio CPF.")
      expect(info.at_css(".ms-info-ok").text).to eq("Entendi")
    end

    it "não mostra os mimos inativos nem os do catálogo antigo (sem níveis)" do
      sushi.update!(active: false)
      MimoItem.create!(name: "Taça de Vinho", icon: "🍷", price_cents: 8_000, receiver_value_cents: 0, active: true)

      get "/mimos/catalogo", params: { receiver_id: clara.id }
      names = Nokogiri::HTML(response.body).css(".ms-card-name").map(&:text)

      expect(names).to eq(%w[Rosa Coroa])
    end

    it "a confirmação antiga volta para o catálogo da mesma pessoa" do
      get "/mimos/confirmar", params: { receiver_id: clara.id, mimo_item_id: rosa.id }

      expect(response).to redirect_to("/mimos/catalogo?receiver_id=#{clara.id}")
    end
  end

  describe "POST /mimo/enviar" do
    before { sign_in luan, scope: :user }

    it "com saldo: paga com a carteira, no nível escolhido, e quem recebe fica com 88%" do
      give_balance(luan, 1_000)

      expect { deliver(receiver_id: clara.id, mimo_item_id: rosa.id, tier: "especial", message: "Pra você 🌹") }
        .to have_enqueued_job(MimoPushNotificationJob)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["status"]).to eq("sent")
      mimo = MimoTransaction.order(:created_at).last
      expect(mimo).to have_attributes(sender: luan, receiver: clara, mimo_item: rosa, tier: "especial",
                                      item_label: "rosa vermelha", price_cents: 490, receiver_value_cents: 431,
                                      status: "completed", message: "Pra você 🌹")
      expect(luan.wallet.reload.balance_cents).to eq(510)
      expect(clara.wallet.reload.balance_cents).to eq(431)
      expect(flash[:notice]).to eq("Mimo enviado para Maria! 🎁")
    end

    it "avisa quem recebeu (notificação que abre a tela do mimo)" do
      give_balance(luan, 1_000)

      deliver(receiver_id: clara.id, mimo_item_id: rosa.id, tier: "simples")

      notification = Notification.find_by(recipient: clara, notifiable: MimoTransaction.order(:created_at).last)
      expect(notification.action).to eq("te enviou um Mimo: Rosa")
    end

    it "o preço é sempre o do servidor (um preço mandado pelo navegador é ignorado)" do
      give_balance(luan, 100_000)

      deliver(receiver_id: clara.id, mimo_item_id: rosa.id, tier: "premium", price_cents: 1, amount_cents: 1)

      expect(MimoTransaction.order(:created_at).last).to have_attributes(price_cents: 990, item_label: "buquê de rosas")
    end

    it "sem saldo suficiente: abre o checkout do Mercado Pago com o mesmo valor" do
      give_balance(luan, 100)
      preference = stub_mercado_pago_checkout

      deliver(receiver_id: clara.id, mimo_item_id: sushi.id, tier: "premium")

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("status" => "checkout", "checkout_url" => "https://mp.test/checkout/1")
      mimo = MimoTransaction.order(:created_at).last
      expect(mimo).to have_attributes(status: "pending", price_cents: 17_990, receiver_value_cents: 15_831, tier: "premium", item_label: "rodízio")
      expect(mimo.mp_fee_cents + mimo.platform_fee_cents).to eq(2_159) # os 12%, com a taxa do MP dentro
      expect(luan.wallet.reload.balance_cents).to eq(100)
      expect(preference).to have_received(:create).with(hash_including(items: [ hash_including(title: "Mimo: Sushi — rodízio", unit_price: 179.9) ]))
    end

    it "recusa nível que não existe" do
      give_balance(luan, 1_000)

      deliver(receiver_id: clara.id, mimo_item_id: rosa.id, tier: "gigante")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(MimoTransaction.count).to eq(0)
    end

    it "recusa recadinho com mais de 80 caracteres" do
      give_balance(luan, 1_000)

      deliver(receiver_id: clara.id, mimo_item_id: rosa.id, tier: "simples", message: "a" * 81)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("80 caracteres")
    end

    describe "Mimo do seu jeito" do
      it "envia o texto e o valor digitados, sem item do catálogo" do
        give_balance(luan, 65_000)

        deliver(receiver_id: clara.id, custom_label: "  Um jantar no Rio Vermelho ", amount_cents: 10_000, message: "Bora? Te espero lá 😉")

        expect(response).to have_http_status(:created)
        mimo = MimoTransaction.order(:created_at).last
        expect(mimo).to have_attributes(mimo_item: nil, tier: nil, item_label: "Um jantar no Rio Vermelho",
                                        price_cents: 10_000, receiver_value_cents: 8_800, status: "completed")
        expect(mimo).to be_custom
        expect(mimo.display_label).to eq("Um jantar no Rio Vermelho")
        expect(clara.wallet.reload.balance_cents).to eq(8_800)
      end

      {
        "abaixo de R$ 5"  => { custom_label: "Um chopp", amount_cents: 499 },
        "acima de R$ 500" => { custom_label: "Um chopp", amount_cents: 50_001 },
        "sem nome"        => { custom_label: "   ", amount_cents: 10_000 },
        "nome com 41"     => { custom_label: "a" * 41, amount_cents: 10_000 }
      }.each do |caso, params|
        it "recusa #{caso}" do
          give_balance(luan, 100_000)

          deliver(params.merge(receiver_id: clara.id))

          expect(response).to have_http_status(:unprocessable_entity)
          expect(MimoTransaction.count).to eq(0)
        end
      end
    end

    it "não envia para si mesmo" do
      give_balance(luan, 1_000)

      deliver(receiver_id: luan.id, mimo_item_id: rosa.id, tier: "simples")

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "exige login" do
      sign_out :user

      deliver(receiver_id: clara.id, mimo_item_id: rosa.id, tier: "simples")

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "app mobile antigo (sem nível)" do
    it "POST /mimo/send_with_wallet só com mimo_item_id cobra o Simples (o preço que o catálogo mostra)" do
      sign_in luan, scope: :user
      give_balance(luan, 1_000)

      post "/mimo/send_with_wallet", params: { receiver_id: clara.id, mimo_item_id: rosa.id }, as: :json

      expect(response).to have_http_status(:created)
      expect(MimoTransaction.order(:created_at).last).to have_attributes(price_cents: 290, tier: "simples", item_label: "rosa")
    end

    it "GET /mimo_items/catalog traz categoria e níveis" do
      sign_in luan, scope: :user

      get "/mimo_items/catalog"

      item = response.parsed_body["items"].find { |i| i["id"] == rosa.id }
      expect(item).to include("category" => "rapidos", "price_cents" => 290, "starting_price_cents" => 290)
      expect(item["tiers"].map { |t| t["price_formatted"] }).to eq([ "R$ 2,90", "R$ 4,90", "R$ 9,90" ])
    end
  end

  describe "Mimo do seu jeito (/mimos/do-seu-jeito)" do
    it "mostra a prévia com o nome de quem recebe, os valores sugeridos e a taxa" do
      sign_in luan, scope: :user
      give_balance(luan, 65_000)

      get "/mimos/do-seu-jeito", params: { receiver_id: clara.id }
      page = Nokogiri::HTML(response.body)

      expect(page.at_css(".ms-title").text).to eq("Mimo do seu jeito")
      expect(page.at_css(".ms-preview-kicker").text).to eq("Como Maria vai ver")
      expect(page.css(".ms-preset").map(&:text)).to eq([ "R$ 100", "R$ 200", "R$ 300", "R$ 500" ])
      expect(page.at_css(".ms-preset.is-active").text).to eq("R$ 100")
      expect(page.at_css("[data-mimo-custom-target=range]").text.squish).to eq("De R$ 5,00 a R$ 500,00 · seu saldo: R$ 650,00")
      expect(page.at_css(".ms-custom-fee").text.squish).to eq("Maria recebe o valor na carteira GeoMatch (taxa de 12%).")
      expect(page.at_css("#ms-custom-label")["maxlength"]).to eq("40")
      expect(page.at_css("#ms-custom-note")["maxlength"]).to eq("80")
    end
  end

  describe "Você ganhou um mimo (/mimos/recebido/:id)" do
    let(:mimo) do
      give_balance(clara, 10_000)
      MimoWalletPaymentService.call(sender: clara, receiver: luan, selection: MimoSelection.from_item(sushi, "simples"),
                                    message: "Bora? Te espero lá 😉")
    end

    before { sign_in luan, scope: :user }

    it "mostra quem enviou, o mimo (com o emoji), o valor e quanto entrou na carteira" do
      get "/mimos/recebido/#{mimo.id}"
      page = Nokogiri::HTML(response.body)

      expect(page.at_css(".mg-emoji").text).to eq("🍣")
      expect(page.at_css(".mg-gift-box")).to be_nil
      expect(page.at_css(".mg-pill").text).to eq("🎁 Você ganhou um mimo")
      expect(page.at_css(".mg-from").text).to eq("Maria Clara te enviou")
      expect(page.at_css(".mg-label").text).to eq("Combinado 20 peças")
      expect(page.at_css(".mg-value").text).to eq("no valor de R$ 59,90")
      expect(page.at_css(".mg-note p").text).to eq("Bora? Te espero lá 😉")
      expect(page.at_css(".mg-note .mg-avatar").text).to eq("MC")
      expect(page.at_css(".mg-wallet").text.squish).to eq("R$ 52,71 entraram na sua carteira")
      expect(page.at_css("[data-mimo-gift-target=thankButton]").text.squish).to eq("Agradecer a Maria Clara")
      expect(page.at_css(".mg-btn--outline")["href"]).to eq("/users/#{clara.id}")
      expect(page.at_css(".mg-link")["href"]).to eq("/carteira")
      expect(page.css(".mg-quick-btn").map(&:text)).to eq([ "Muito obrigado! 🥰", "Adorei, bora! 😍", "Você é demais ❤️", "Que surpresa boa! ✨" ])
    end

    it "no Mimo do seu jeito mostra a caixa de presente no lugar do emoji" do
      give_balance(clara, 20_000)
      custom = MimoWalletPaymentService.call(sender: clara, receiver: luan,
                                             selection: MimoSelection.custom(label: "Um jantar no Rio Vermelho", amount_cents: 10_000))

      get "/mimos/recebido/#{custom.id}"
      page = Nokogiri::HTML(response.body)

      expect(page.at_css("svg.mg-gift-box")).to be_present
      expect(page.at_css(".mg-emoji")).to be_nil
      expect(page.at_css(".mg-label").text).to eq("Um jantar no Rio Vermelho")
      expect(page.at_css(".mg-wallet").text.squish).to eq("R$ 88,00 entraram na sua carteira")
    end

    it "depois de agradecer, o botão fica como 'Agradecimento enviado'" do
      mimo.update!(thanked_at: Time.current)

      get "/mimos/recebido/#{mimo.id}"
      button = Nokogiri::HTML(response.body).at_css("[data-mimo-gift-target=thankButton]")

      expect(button.text.squish).to eq("Agradecimento enviado")
      expect(button["disabled"]).to be_present
    end

    it "não abre o mimo de outra pessoa" do
      other = create(:user, onboarding_completed: true)
      sign_in other, scope: :user

      get "/mimos/recebido/#{mimo.id}"

      expect(response).to redirect_to("/carteira")
    end
  end

  describe "POST /mimos/recebido/:id/agradecer" do
    let(:mimo) do
      give_balance(clara, 1_000)
      MimoWalletPaymentService.call(sender: clara, receiver: luan, selection: MimoSelection.from_item(rosa, "especial"))
    end

    before { sign_in luan, scope: :user }

    def thank(message)
      post "/mimos/recebido/#{mimo.id}/agradecer", params: { message: message }, as: :json
    end

    it "sem conversa ainda: cria a conversa e manda a mensagem nela" do
      expect { thank("Muito obrigado! 🥰 Que dia fica bom pra você?") }.to change(Match, :count).by(1)

      expect(response).to have_http_status(:created)
      match = Match.last
      expect([ match.user, match.matched_user ]).to contain_exactly(clara, luan)
      expect(match.messages.last).to have_attributes(sender: luan, content: "Muito obrigado! 🥰 Que dia fica bom pra você?")
      expect(response.parsed_body["match_url"]).to eq("/matches/#{match.id}")
      expect(mimo.reload).to be_thanked
    end

    it "com conversa: usa a mesma" do
      match = Match.create!(user: luan, matched_user: clara)

      expect { thank("Adorei, bora! 😍") }.not_to change(Match, :count)
      expect(match.messages.last.content).to eq("Adorei, bora! 😍")
    end

    it "agradece uma vez só" do
      thank("Muito obrigado!")
      thank("De novo")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Você já agradeceu este mimo.")
      expect(Message.where(sender: luan).count).to eq(1)
    end

    it "recusa mensagem vazia ou com mais de 200 caracteres" do
      thank("  ")
      expect(response).to have_http_status(:unprocessable_entity)

      thank("a" * 201)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(mimo.reload).not_to be_thanked
    end

    it "não cria conversa com quem está bloqueado" do
      luan.blocks_sent.create!(blocked: clara)

      expect { thank("Obrigado") }.not_to change(Match, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "não recria a conversa se quem mandou o mimo desfez o match" do
      Like.create!(liker: clara, liked: luan, is_like: false)

      expect { thank("Obrigado") }.not_to change(Match, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "só quem recebeu pode agradecer" do
      sign_in create(:user, onboarding_completed: true), scope: :user

      thank("Obrigado")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "extrato da carteira" do
    it "mostra o mimo recebido (com link para a tela dele) e o enviado com saldo" do
      give_balance(clara, 1_000)
      received = MimoWalletPaymentService.call(sender: clara, receiver: luan, selection: MimoSelection.from_item(rosa, "premium"))
      give_balance(luan, 1_000)
      MimoWalletPaymentService.call(sender: luan, receiver: clara, selection: MimoSelection.from_item(rosa, "simples"))
      sign_in luan, scope: :user

      get "/wallet/transactions"
      entries = response.parsed_body["transactions"].index_by { |e| e["type"] }

      expect(entries["mimo_received"]).to include("amount_cents" => 871, "description" => "Mimo de Maria Clara: Buquê de rosas",
                                                  "url" => "/mimos/recebido/#{received.id}")
      expect(entries["mimo_sent"]).to include("amount_cents" => -290, "description" => "Mimo para Maria Clara: Rosa")
    end
  end
end
