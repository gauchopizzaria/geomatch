# Catálogo de Mimos (presentes virtuais) — ver app/models/mimo_item.rb.
#
# Fonte: tabela interna "Catálogo de mimos e valores" (48 mimos em 8 categorias, cada
# um com 3 níveis: Simples · Especial · Premium). Valores em reais, pagos por quem envia.
#
# Arquivo separado de db/seeds.rb (que apaga usuários a cada execução) para poder
# popular/atualizar só o catálogo sem mexer nos dados de teste. Pode ser rodado
# sozinho, quantas vezes precisar (atualiza pelo nome): bin/rails runner db/seeds/mimos.rb
#
# Os mimos do catálogo antigo (Taça de Vinho, Jantar Completo...) ficam inativos: somem
# da tela, mas continuam no banco porque há envios que apontam para eles.
#
# receiver_value_cents é só a referência estática do item (preço do Simples − 12%) — o
# crédito real ao destinatário é recalculado no envio por MimoFeeCalculator.

# [nome, emoji, [simples, preço], [especial, preço], [premium, preço], descrição opcional]
MIMO_CATALOG = {
  "rapidos" => [
    [ "Rosa",       "🌹", [ "rosa", 290 ],       [ "rosa vermelha", 490 ],     [ "buquê de rosas", 990 ] ],
    [ "Coração",    "❤️", [ "coração", 290 ],    [ "coração brilhante", 490 ], [ "chuva de corações", 990 ] ],
    [ "Piscadinha", "😉", [ "piscadinha", 190 ], [ "beijinho", 390 ],          [ "abraço apertado", 690 ] ]
  ],
  "bebidas" => [
    [ "Água de coco",     "🥥", [ "coco gelado", 790 ],   [ "coco grande", 1_290 ],        [ "garrafa 1L", 1_990 ] ],
    [ "Café",             "☕", [ "espresso", 790 ],      [ "cappuccino", 1_490 ],         [ "café especial + doce", 2_490 ] ],
    [ "Energético",       "⚡", [ "lata", 1_290 ],        [ "lata grande", 1_990 ],        [ "drink com energético", 2_990 ] ],
    [ "Cerveja / chopp",  "🍺", [ "long neck", 990 ],     [ "chopp 500ml", 1_690 ],        [ "chopp artesanal", 2_990 ] ],
    [ "Drink",            "🍹", [ "caipirinha", 1_990 ],  [ "caipiroska / gin", 3_490 ],   [ "drink autoral", 5_490 ] ],
    [ "Balde de cerveja", "🍻", [ "5 long necks", 4_990 ], [ "10 long necks", 7_990 ],     [ "balde premium", 11_990 ] ],
    [ "Vinho",            "🍷", [ "nacional", 6_990 ],    [ "importado", 12_990 ],         [ "reserva", 29_990 ] ],
    [ "Espumante",        "🥂", [ "nacional", 7_990 ],    [ "prosecco", 15_990 ],          [ "espumante premium", 34_990 ] ],
    [ "Champanhe",        "🍾", [ "champanhe", 39_990 ],  [ "champanhe premium", 79_990 ], [ "edição especial", 149_990 ] ]
  ],
  "comidas" => [
    [ "Picolé / sorvete", "🍦", [ "picolé", 990 ],               [ "paleta gourmet", 1_990 ], [ "pote premium", 2_990 ] ],
    [ "Acarajé",          "🧆", [ "simples", 1_290 ],            [ "completo", 1_990 ],       [ "acarajé + bebida", 2_990 ] ],
    [ "Crepe",            "🥞", [ "salgado", 1_990 ],            [ "recheado", 2_990 ],       [ "doce + salgado", 3_990 ] ],
    [ "Pizza",            "🍕", [ "fatia", 1_490 ],              [ "pizza média", 5_990 ],    [ "pizza grande premium", 9_990 ] ],
    [ "Açaí",             "🍇", [ "300ml", 2_490 ],              [ "500ml", 3_990 ],          [ "700ml completo", 5_990 ] ],
    [ "Hambúrguer",       "🍔", [ "smash", 2_990 ],              [ "artesanal", 4_990 ],      [ "combo artesanal", 7_990 ] ],
    [ "Sushi",            "🍣", [ "combinado 20 peças", 5_990 ], [ "40 peças", 9_990 ],       [ "rodízio", 17_990 ] ],
    [ "Jantar a dois",    "🕯️", [ "casual", 19_990 ],            [ "restaurante", 34_990 ],   [ "alta gastronomia", 69_990 ] ]
  ],
  "beleza" => [
    [ "Esmaltação",          "💅", [ "mão", 2_990 ],           [ "pé e mão", 4_990 ],           [ "em gel", 8_990 ] ],
    [ "Barbearia",           "💈", [ "corte", 3_990 ],         [ "corte + barba", 6_990 ],      [ "dia do barbeiro", 11_990 ] ],
    [ "Cabelo",              "💇", [ "escova", 4_990 ],        [ "hidratação + escova", 8_990 ], [ "tratamento completo", 14_990 ] ],
    [ "Kit skincare",        "🧴", [ "básico", 7_990 ],        [ "completo", 14_990 ],          [ "premium", 29_990 ] ],
    [ "Massagem",            "💆", [ "30 min", 9_990 ],        [ "60 min", 15_990 ],            [ "pedras quentes", 24_990 ] ],
    [ "Kit salão de beleza", "💄", [ "cabelo + unha", 14_990 ], [ "+ maquiagem", 24_990 ],      [ "dia da noiva", 44_990 ] ],
    [ "Day spa",             "🧖", [ "meio período", 24_990 ], [ "dia inteiro", 44_990 ],       [ "spa a dois", 79_990 ] ]
  ],
  "presentes" => [
    [ "Chocolate",         "🍫", [ "barra", 1_490 ],      [ "caixa de bombons", 3_990 ],  [ "chocolate premium", 8_990 ] ],
    [ "Flores",            "💐", [ "rosa única", 2_990 ], [ "buquê", 7_990 ],             [ "arranjo especial", 15_990 ] ],
    [ "Camisa",            "👕", [ "básica", 6_990 ],     [ "de marca", 12_990 ],         [ "grife", 24_990 ] ],
    [ "Camisa de time",    "⚽", [ "torcedor", 19_990 ],  [ "oficial", 34_990 ],          [ "versão jogador", 49_990 ] ],
    [ "Óculos de sol",     "🕶️", [ "casual", 9_990 ],     [ "de marca", 24_990 ],         [ "grife", 69_990 ] ],
    [ "Perfume",           "🌸", [ "nacional", 15_990 ],  [ "nacional premium", 24_990 ], [ "lançamento", 37_990 ] ],
    [ "Perfume importado", "🌷", [ "importado", 39_990 ], [ "importado de marca", 69_990 ], [ "grife", 129_990 ] ]
  ],
  "fitness" => [
    [ "Isotônico",           "💧", [ "isotônico", 790 ],     [ "bebida proteica", 1_290 ], [ "kit hidratação", 1_990 ] ],
    [ "Diária de academia",  "🏋️", [ "diária", 2_990 ],      [ "diária premium", 4_990 ],  [ "aula especial", 7_990 ] ],
    [ "1 mês de academia",   "💪", [ "plano básico", 9_990 ], [ "plano rede", 13_990 ],     [ "academia premium", 29_990 ] ],
    [ "Inscrição de corrida", "👟", [ "5 km", 8_990 ],        [ "10 km", 14_990 ],          [ "meia maratona", 24_990 ] ],
    [ "Suplemento",          "🥤", [ "creatina", 9_990 ],     [ "whey", 16_990 ],           [ "kit completo", 24_990 ] ]
  ],
  "role" => [
    [ "Uber",            "🚗", [ "corrida curta", 1_990 ], [ "média", 3_990 ],               [ "longa / carro premium", 6_990 ] ],
    [ "Cinema",          "🎬", [ "ingresso", 2_990 ],      [ "ingresso + pipoca", 5_990 ],   [ "sala VIP", 9_990 ] ],
    [ "Balada",          "🪩", [ "pista", 4_990 ],         [ "área VIP", 9_990 ],            [ "open bar", 19_990 ] ],
    [ "Show",            "🎶", [ "pista", 14_990 ],        [ "pista premium", 29_990 ],      [ "camarote", 59_990 ] ],
    [ "Passeio de barco", "🛥️", [ "escuna", 14_990 ],       [ "lancha compartilhada", 29_990 ], [ "passeio privativo", 119_990 ] ],
    [ "Camarote",        "🎟️", [ "camarote", 49_990 ],     [ "camarote open bar", 99_990 ],  [ "camarote VIP", 199_990 ] ]
  ],
  "vip" => [
    [ "Coroa",                  "👑", [ "coroa", 99_990 ],     [ "coroa de ouro", 199_990 ], [ "coroa de diamante", 499_990 ], "Rei/Rainha do rolê" ],
    [ "Fim de semana na praia", "🏖️", [ "1 noite", 149_990 ],  [ "2 noites", 299_990 ],      [ "resort", 599_990 ] ],
    [ "Diamante",               "💎", [ "diamante", 299_990 ], [ "diamante raro", 499_990 ], [ "diamante lendário", 999_990 ] ]
  ]
}.freeze

puts "Cadastrando catálogo de Mimos..."

position  = 0
new_names = []

MimoItem.transaction do
  MimoItem::CATEGORIES.each do |category|
    MIMO_CATALOG.fetch(category[:key]).each do |name, icon, simples, especial, premium, description|
      position += 1
      tiers = MimoItem::TIER_KEYS.zip([ simples, especial, premium ]).map do |key, (label, cents)|
        { "key" => key, "label" => label, "price_cents" => cents }
      end

      item = MimoItem.find_or_initialize_by(name: name)
      item.assign_attributes(
        category: category[:key],
        icon: icon,
        description: description,
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

  # Catálogo antigo: sai da tela, fica no banco (envios antigos apontam para ele)
  retired = MimoItem.where.not(name: new_names).where(active: true).update_all(active: false, updated_at: Time.current)
  puts "  #{retired} mimo(s) do catálogo antigo desativado(s)." if retired.positive?
end

puts "Catálogo de Mimos: #{MimoItem.active.count} mimos ativos em #{MimoItem.active.distinct.count(:category)} categorias."
