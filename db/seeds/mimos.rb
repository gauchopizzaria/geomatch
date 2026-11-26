# Catálogo de Mimos (presentes virtuais) — ver app/models/mimo_item.rb.
#
# Fonte: a tela "Enviar um Mimo" (mockup do catálogo) — 48 mimos em 8 categorias, 6 em
# cada uma, na ordem da tela. O preço do Simples é o "a partir de" que aparece no card.
#
# Os níveis Especial e Premium:
#   # tabela   → copiados da tabela interna "Catálogo de mimos e valores" (o mimo existe
#                lá com o mesmo preço de Simples);
#   # sugerido → nomes e preços propostos para completar os três níveis (o mockup só
#                mostra o "a partir de"). Revise e ajuste aqui à vontade.
#
# Arquivo separado de db/seeds.rb (que apaga usuários a cada execução) para poder
# popular/atualizar só o catálogo sem mexer nos dados de teste. Pode ser rodado
# sozinho, quantas vezes precisar (atualiza pelo nome): bin/rails runner db/seeds/mimos.rb
#
# Mimos que saíram do catálogo ficam inativos: somem da tela, mas continuam no banco
# porque há envios que apontam para eles.
#
# receiver_value_cents é só a referência estática do item (preço do Simples − 12%) — o
# crédito real ao destinatário é recalculado no envio por MimoFeeCalculator.

# [nome, emoji, [simples, preço], [especial, preço], [premium, preço]]
MIMO_CATALOG = {
  "rapidos" => [
    [ "Rosa",       "🌹", [ "rosa", 290 ],       [ "rosa vermelha", 490 ],     [ "buquê de rosas", 990 ] ],      # tabela
    [ "Coração",    "❤️", [ "coração", 290 ],    [ "coração brilhante", 490 ], [ "chuva de corações", 990 ] ],   # tabela
    [ "Piscadinha", "😉", [ "piscadinha", 190 ], [ "piscadinha dupla", 390 ],  [ "piscadinha + abraço", 690 ] ], # sugerido
    [ "Beijinho",   "💋", [ "beijinho", 190 ],   [ "beijo estalado", 390 ],    [ "chuva de beijos", 690 ] ],     # sugerido
    [ "Bombom",     "🍫", [ "bombom", 390 ],     [ "trio de bombons", 690 ],   [ "caixa de bombons", 1_290 ] ],  # sugerido
    [ "Estrela",    "⭐", [ "estrela", 490 ],    [ "estrela brilhante", 890 ], [ "chuva de estrelas", 1_490 ] ]  # sugerido
  ],
  "bebidas" => [
    [ "Água de coco", "🥥", [ "coco gelado", 790 ],     [ "coco grande", 1_290 ],      [ "garrafa 1L", 1_990 ] ],           # tabela
    [ "Café",         "☕", [ "espresso", 790 ],        [ "cappuccino", 1_490 ],       [ "café especial + doce", 2_490 ] ], # tabela
    [ "Energético",   "⚡", [ "lata", 1_290 ],          [ "lata grande", 1_990 ],      [ "drink com energético", 2_990 ] ], # tabela
    [ "Chopp",        "🍺", [ "chopp 300ml", 1_490 ],   [ "chopp 500ml", 1_990 ],      [ "chopp artesanal", 2_990 ] ],      # sugerido
    [ "Drink",        "🍹", [ "caipirinha", 1_990 ],    [ "caipiroska / gin", 3_490 ], [ "drink autoral", 5_490 ] ],        # tabela
    [ "Vinho",        "🍷", [ "taça de vinho", 3_990 ], [ "garrafa nacional", 6_990 ], [ "garrafa importada", 12_990 ] ]    # sugerido
  ],
  "comidas" => [
    [ "Sorvete",    "🍨", [ "picolé", 890 ],               [ "paleta gourmet", 1_690 ], [ "pote premium", 2_990 ] ],         # sugerido
    [ "Açaí",       "🍇", [ "300ml", 1_490 ],              [ "500ml", 2_490 ],          [ "700ml completo", 3_990 ] ],       # sugerido
    [ "Hambúrguer", "🍔", [ "smash", 2_990 ],              [ "artesanal", 4_990 ],      [ "combo artesanal", 7_990 ] ],      # tabela
    [ "Pizza",      "🍕", [ "pizza média", 3_990 ],        [ "pizza grande", 5_990 ],   [ "pizza grande premium", 8_990 ] ], # sugerido
    [ "Sushi",      "🍣", [ "combinado 20 peças", 4_990 ], [ "40 peças", 8_990 ],       [ "rodízio", 14_990 ] ],             # sugerido
    [ "Bolo",       "🍰", [ "fatia de bolo", 1_690 ],      [ "bolo pequeno", 3_990 ],   [ "bolo decorado", 8_990 ] ]         # sugerido
  ],
  "beleza" => [
    [ "Esmalte",    "💅", [ "esmalte", 1_490 ],         [ "esmaltação mão", 2_990 ],      [ "pé e mão", 4_990 ] ],              # sugerido
    [ "Batom",      "💄", [ "batom", 2_990 ],           [ "batom de marca", 5_990 ],      [ "kit de maquiagem", 11_990 ] ],     # sugerido
    [ "Hidratante", "🧴", [ "hidratante", 3_490 ],      [ "kit skincare básico", 7_990 ], [ "kit skincare completo", 14_990 ] ], # sugerido
    [ "Perfume",    "🌸", [ "body splash", 5_990 ],     [ "perfume nacional", 12_990 ],   [ "perfume importado", 29_990 ] ],    # sugerido
    [ "Spa",        "💆", [ "massagem 30 min", 9_990 ], [ "massagem 60 min", 15_990 ],    [ "day spa", 24_990 ] ],              # sugerido
    [ "Salão",      "✂️", [ "corte", 7_990 ],           [ "corte + escova", 12_990 ],     [ "dia de salão", 24_990 ] ]          # sugerido
  ],
  "presentes" => [
    [ "Buquê",    "💐", [ "buquê pequeno", 3_990 ],  [ "buquê", 7_990 ],              [ "arranjo especial", 15_990 ] ], # sugerido
    [ "Ursinho",  "🧸", [ "ursinho", 2_990 ],        [ "ursinho médio", 5_990 ],      [ "ursão gigante", 12_990 ] ],    # sugerido
    [ "Surpresa", "🎁", [ "caixa surpresa", 4_990 ], [ "caixa especial", 9_990 ],     [ "caixa premium", 19_990 ] ],    # sugerido
    [ "Cartinha", "💌", [ "cartinha", 990 ],         [ "cartinha perfumada", 1_490 ], [ "carta + flores", 2_990 ] ],    # sugerido
    [ "Joia",     "💍", [ "pulseira", 9_990 ],       [ "colar", 19_990 ],             [ "anel", 39_990 ] ],             # sugerido
    [ "Laço",     "🎀", [ "laço", 1_990 ],           [ "laço de cetim", 3_490 ],      [ "kit de laços", 5_990 ] ]       # sugerido
  ],
  "fitness" => [
    [ "Garrafinha",   "💧", [ "garrafinha", 1_990 ],     [ "garrafa térmica", 4_990 ],    [ "garrafa premium", 8_990 ] ], # sugerido
    [ "Shake",        "🥤", [ "shake", 2_490 ],          [ "shake proteico", 3_490 ],     [ "kit de shakes", 6_990 ] ],   # sugerido
    [ "Aula de yoga", "🧘", [ "aula avulsa", 3_990 ],    [ "aula particular", 8_990 ],    [ "pacote 4 aulas", 14_990 ] ], # sugerido
    [ "Personal",     "🏋️", [ "treino avulso", 7_990 ],  [ "2 treinos", 14_990 ],         [ "4 treinos", 27_990 ] ],      # sugerido
    [ "Corrida",      "👟", [ "inscrição 5 km", 2_990 ], [ "10 km", 5_990 ],              [ "meia maratona", 12_990 ] ],  # sugerido
    [ "Bike",         "🚴", [ "aluguel 1 hora", 3_490 ], [ "aluguel por um dia", 6_990 ], [ "passeio guiado", 11_990 ] ]  # sugerido
  ],
  "role" => [
    [ "Cinema",  "🎬", [ "ingresso", 2_990 ],             [ "ingresso + pipoca", 5_990 ],   [ "sala VIP", 9_990 ] ],              # tabela
    [ "Praia",   "🏖️", [ "cadeira e guarda-sol", 1_990 ], [ "petiscos na barraca", 5_990 ], [ "dia de praia completo", 11_990 ] ], # sugerido
    [ "Karaokê", "🎤", [ "1 hora", 3_990 ],               [ "sala por 2 horas", 7_990 ],    [ "sala VIP", 14_990 ] ],             # sugerido
    [ "Show",    "🎶", [ "pista", 9_990 ],                [ "pista premium", 19_990 ],      [ "camarote", 39_990 ] ],             # sugerido
    [ "Balada",  "🪩", [ "pista", 4_990 ],                [ "área VIP", 9_990 ],            [ "open bar", 19_990 ] ],             # tabela
    [ "Boliche", "🎳", [ "partida", 6_490 ],              [ "partida + petiscos", 10_990 ], [ "pista VIP", 18_990 ] ]             # sugerido
  ],
  "vip" => [
    [ "Champanhe",     "🍾", [ "champanhe", 19_990 ],         [ "champanhe premium", 39_990 ], [ "edição especial", 79_990 ] ],    # sugerido
    [ "Jantar a dois", "🕯️", [ "restaurante", 24_590 ],       [ "alta gastronomia", 44_990 ],  [ "jantar exclusivo", 89_990 ] ],   # sugerido
    [ "Coroa",         "👑", [ "coroa", 9_990 ],              [ "coroa de ouro", 19_990 ],     [ "coroa de diamante", 49_990 ] ],  # sugerido
    [ "Diamante",      "💎", [ "diamante", 49_990 ],          [ "diamante raro", 99_990 ],     [ "diamante lendário", 199_990 ] ], # sugerido
    [ "Passeio",       "🛥️", [ "passeio de lancha", 39_990 ], [ "lancha privativa", 79_990 ],  [ "iate", 149_990 ] ],              # sugerido
    [ "Destaque",      "🌟", [ "destaque", 14_990 ],          [ "destaque dourado", 29_990 ],  [ "destaque lendário", 59_990 ] ]   # sugerido
  ]
}.freeze

puts "Cadastrando catálogo de Mimos..."

position  = 0
new_names = []

MimoItem.transaction do
  MimoItem::CATEGORIES.each do |category|
    MIMO_CATALOG.fetch(category[:key]).each do |name, icon, simples, especial, premium|
      position += 1
      tiers = MimoItem::TIER_KEYS.zip([ simples, especial, premium ]).map do |key, (label, cents)|
        { "key" => key, "label" => label, "price_cents" => cents }
      end

      item = MimoItem.find_or_initialize_by(name: name)
      item.assign_attributes(
        category: category[:key],
        icon: icon,
        description: nil,
        position: position,
        tiers: tiers,
        price_cents: simples.last,
        receiver_value_cents: MimoFeeCalculator.receiver_value_cents(simples.last),
        active: true
      )
      item.save!
      new_names << name
    end
  end

  # Mimos fora desta lista: saem da tela, ficam no banco (envios antigos apontam para eles)
  retired = MimoItem.where.not(name: new_names).where(active: true).update_all(active: false, updated_at: Time.current)
  puts "  #{retired} mimo(s) que saíram do catálogo desativado(s)." if retired.positive?
end

puts "Catálogo de Mimos: #{MimoItem.active.count} mimos ativos em #{MimoItem.active.distinct.count(:category)} categorias."
