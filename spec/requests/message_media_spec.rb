require "rails_helper"

# Mensagem de voz e foto no chat (MessageMedia + MessagesController#create)
RSpec.describe "Mídia no chat (áudio e foto)", type: :request do
  let(:me)    { create(:user, username: "Samuel", onboarding_completed: true) }
  let(:clara) { create(:user, username: "Maria Clara", onboarding_completed: true) }
  let!(:match) { Match.create!(user: me, matched_user: clara) }

  # Começo de arquivo de cada formato — é o que a conferência do conteúdo olha
  WEBM = "\x1A\x45\xDF\xA3\x9F\x42\x86\x81\x01\x42\xF7\x81\x01\x42\xF2\x81\x04\x42\xF3\x81\x08\x42\x82\x84webm".b + ("\x00".b * 64)
  M4A  = "\x00\x00\x00\x1Cftypmp42\x00\x00\x00\x01isommp41mp42".b + ("\x00".b * 64)
  PNG  = ("\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1F\x15\xC4\x89" \
          "\x00\x00\x00\rIDATx\x9Cc\xF8\xCF\xC0\xF0\x1F\x00\x05\x00\x01\xFF\x89\x99=\x1D\x00\x00\x00\x00IEND\xAEB`\x82").b

  before do
    sign_in me, scope: :user
    allow(MatchChannel).to receive(:broadcast_to)
    allow(PushNotificationJob).to receive(:perform_later)
  end

  def upload(bytes, content_type, name)
    file = Tempfile.new([ "midia", File.extname(name) ], binmode: true)
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: name)
  end

  def send_audio(bytes: WEBM, type: "audio/webm;codecs=opus", name: "voz.webm", duration: "7.4", peaks: "10,80,45,300,-5", **extra)
    post "/matches/#{match.id}/messages",
         params: { message: { audio: upload(bytes, type, name), audio_duration: duration, audio_peaks: peaks }.merge(extra) }
  end

  def send_photo(bytes: PNG, type: "image/png", name: "foto.png", **extra)
    post "/matches/#{match.id}/messages",
         params: { message: { photo: upload(bytes, type, name), photo_width: "1200", photo_height: "900" }.merge(extra) }
  end

  describe "mensagem de voz" do
    it "salva o áudio com duração e onda, e o content vira o rótulo da lista e do push" do
      expect { send_audio }.to change { match.messages.count }.by(1)

      expect(response).to have_http_status(:ok)
      message = match.messages.last
      expect(message).to have_attributes(kind: "audio", content: "🎤 Mensagem de voz (0:07)", sender_id: me.id)
      expect(message.audio.blob).to have_attributes(content_type: "audio/webm", byte_size: WEBM.bytesize)
      expect(message.audio.blob.filename.to_s).to eq("voz.webm")
      expect(message.audio_duration).to eq(7.4)
      expect(message.audio_peaks).to eq([ 10, 80, 45, 100, 0 ]) # fora de 0–100 é ajustado
      expect(message.audio.download).to eq(WEBM)
    end

    it "devolve e transmite a mensagem pronta para o balão (endereço, duração e onda)" do
      send_audio

      message = match.messages.last
      path    = Rails.application.routes.url_helpers.rails_blob_path(message.audio, only_path: true)
      audio   = { url: path, fallback_url: path, duration: 7.4, peaks: [ 10, 80, 45, 100, 0 ] }

      expect(response.parsed_body["chat"]).to include("id" => message.id, "kind" => "audio", "photo" => nil)
      expect(response.parsed_body["chat"]["audio"]).to eq(audio.as_json)
      expect(MatchChannel).to have_received(:broadcast_to)
        .with(match, { message: hash_including(id: message.id, kind: "audio", audio: audio) })
    end

    it "o arquivo já está no armazenamento quando o broadcast sai" do
      stored = nil
      allow(MatchChannel).to receive(:broadcast_to) do |_match, payload|
        blob = Message.find(payload[:message][:id]).audio.blob
        stored = blob.service.exist?(blob.key)
      end

      send_audio

      expect(stored).to be(true)
    end

    it "aceita o que o iPhone grava (audio/mp4)" do
      send_audio(bytes: M4A, type: "audio/mp4", name: "voz.mp4", duration: "65")

      message = match.messages.last
      expect(message.content).to eq("🎤 Mensagem de voz (1:05)")
      expect(message.audio.blob).to have_attributes(content_type: "audio/mp4")
      expect(message.audio.blob.filename.to_s).to eq("voz.m4a")
    end

    it "pode ser a resposta a uma mensagem da conversa" do
      original = match.messages.create!(sender: clara, content: "Me manda um áudio, é mais rápido")

      send_audio(reply_to_id: original.id)

      expect(match.messages.last.reply_to).to eq(original)
    end

    it "limita a duração ao máximo do gravador" do
      send_audio(duration: "9999")

      expect(match.messages.last.audio_duration).to eq(MessageMedia::AUDIO_MAX_DURATION.to_f)
    end

    {
      "sem duração (toque sem querer)" => { duration: "0.3" },
      "com tipo que não é áudio"       => { type: "text/html", name: "voz.html" },
      "com imagem no lugar do áudio"   => { bytes: PNG },
      "vazio"                          => { bytes: "" }
    }.each do |caso, options|
      it "recusa o áudio #{caso}, sem criar mensagem nem deixar arquivo" do
        expect { send_audio(**options) }
          .to change { match.messages.count }.by(0).and change { ActiveStorage::Blob.count }.by(0)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to be_present
        expect(MatchChannel).not_to have_received(:broadcast_to)
      end
    end

    it "recusa áudio grande demais" do
      stub_const("MessageMedia::AUDIO_MAX_SIZE", 50)

      send_audio

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("O áudio é grande demais.")
    end

    it "se o armazenamento falhar, avisa e não deixa mensagem sem arquivo" do
      allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_raise(ActiveStorage::IntegrityError)

      expect { send_audio }.not_to(change { match.messages.count })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Não foi possível enviar o áudio agora.")
    end

    it "não pode ser editada" do
      send_audio
      message = match.messages.last

      patch "/matches/#{match.id}/messages/#{message.id}", params: { message: { content: "texto" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(message.reload.content).to eq("🎤 Mensagem de voz (0:07)")
    end

    it "apagar para todos leva o arquivo junto" do
      send_audio
      message = match.messages.last

      expect { delete "/matches/#{match.id}/messages/#{message.id}", as: :json }
        .to have_enqueued_job(ActiveStorage::PurgeJob)
      expect(Message.exists?(message.id)).to be(false)
    end
  end

  describe "foto" do
    it "salva a foto com o tamanho e o rótulo" do
      expect { send_photo }.to change { match.messages.count }.by(1)

      message = match.messages.last
      expect(message).to have_attributes(kind: "photo", content: "📷 Foto")
      expect(message.photo.blob).to have_attributes(content_type: "image/png")
      expect(response.parsed_body["chat"]["photo"]).to eq(
        "url"    => Rails.application.routes.url_helpers.rails_blob_path(message.photo, only_path: true),
        "width"  => 1200,
        "height" => 900
      )
      expect(response.parsed_body["chat"]["audio"]).to be_nil
    end

    it "recusa arquivo que não é imagem" do
      expect { send_photo(bytes: "<html><script>alert(1)</script></html>", type: "image/png") }
        .not_to(change { match.messages.count })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "recusa formato fora da lista" do
      send_photo(type: "image/svg+xml", name: "foto.svg")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("JPG, PNG ou WebP")
    end
  end

  describe "quem não é da conversa" do
    it "não envia mídia para a conversa de outras pessoas" do
      stranger = create(:user, onboarding_completed: true)
      sign_in stranger, scope: :user

      expect { send_audio }.not_to(change { Message.count })
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "texto continua como antes" do
    it "envia mensagem de texto por JSON" do
      post "/matches/#{match.id}/messages", params: { message: { content: "Mandei! Escuta aí" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(match.messages.last).to have_attributes(content: "Mandei! Escuta aí", kind: "text")
      expect(response.parsed_body["chat"]).to include("kind" => "text", "audio" => nil, "photo" => nil)
    end

    it "recusa texto vazio" do
      post "/matches/#{match.id}/messages", params: { message: { content: " " } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "tela da conversa (/matches/:id)" do
    it "desenha o balão de áudio com tocar, onda e duração, e o de foto" do
      send_audio
      send_photo
      audio_message, photo_message = match.messages.order(:id).last(2)

      get "/matches/#{match.id}"
      page = Nokogiri::HTML(response.body)

      audio = page.at_css("#msg-#{audio_message.id} .message-bubble.is-audio .msg-audio")
      expect(audio["data-url"]).to eq(audio_message.audio_preview[:url])
      expect(audio["data-duration"]).to eq("7.4")
      expect(audio.at_css("button.msg-audio-play")["aria-label"]).to eq("Tocar áudio")
      expect(audio.css(".msg-audio-wave i").size).to eq(MessageMedia::AUDIO_PEAKS)
      expect(audio.at_css(".msg-audio-time").text).to eq("0:07")
      expect(page.at_css("#msg-#{audio_message.id}")["data-kind"]).to eq("audio")

      photo = page.at_css("#msg-#{photo_message.id} .message-bubble.is-photo img.msg-photo")
      expect(photo["src"]).to eq(photo_message.photo_preview[:url])
      expect(photo["width"]).to eq("1200")
    end

    it "tem o microfone, o gravador e o painel do + com Fotos, Câmera e Mimo" do
      get "/matches/#{match.id}"
      page = Nokogiri::HTML(response.body)

      expect(page.at_css("#mic-button")["aria-label"]).to eq("Gravar áudio")
      expect(page.at_css("#rec-hold .rec-slide").text.squish).to eq("Deslize para cancelar")
      expect(page.css("#rec-locked button").map { |b| b["aria-label"] }).to eq([ "Apagar gravação", "Pausar gravação", "Enviar áudio" ])

      # Vibração no iPhone sem o handler nativo: rótulos no microfone e nos botões da
      # gravação apontando para o interruptor escondido (ver chat/haptics.js)
      expect(page.at_css("input#chat-haptic-switch[type=checkbox][switch]")).to be_present
      expect(page.css("label.haptic-tap[for=chat-haptic-switch]").map { |l| l.parent["id"] })
        .to eq(%w[mic-button rec-trash rec-pause rec-send])

      expect(page.css("#chat-attach .chat-attach-card strong").map(&:text)).to eq(%w[Fotos Câmera])
      expect(page.css("#chat-attach .chat-attach-card > span:last-child").map(&:text)).to eq([ "Da sua galeria", "Tirar foto agora" ])
      expect(page.at_css("#chat-attach .chat-attach-note").text.squish).to eq("Só envie fotos que você se sentiria bem em mostrar")
      expect(page.at_css("#chat-attach a.chat-attach-mimo")["href"]).to eq("/mimos/catalogo?receiver_id=#{clara.id}")
      expect(page.at_css("#chat-photo-camera")["capture"]).to eq("environment")
    end
  end

  describe "API mobile (GET /api/v1/messages)" do
    it "informa o tipo e o endereço da mídia" do
      send_audio
      token = JwtService.encode(sub: me.id)

      get "/api/v1/messages", params: { match_id: match.id },
                              headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      item = response.parsed_body["messages"].last
      expect(item).to include("kind" => "audio", "content" => "🎤 Mensagem de voz (0:07)")
      expect(item["audio"]).to include("duration" => 7.4, "peaks" => [ 10, 80, 45, 100, 0 ])
      expect(item["audio"]["url"]).to start_with("http")
    end
  end
end
