# Envio de Mimos com níveis, "Mimo do seu jeito" e agradecimento:
#   tier        — nível escolhido do catálogo ("simples", "especial", "premium");
#                 vazio no Mimo do seu jeito.
#   item_label  — o que quem recebe lê, congelado no envio: o nome do nível
#                 ("rosa vermelha") ou o texto digitado ("Um jantar no Rio Vermelho").
#   thanked_at  — quando quem recebeu agradeceu (o botão vira "Agradecimento enviado").
#   mimo_item_id passa a aceitar nulo: o Mimo do seu jeito não vem do catálogo.
class AddTierLabelAndThanksToMimoTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :mimo_transactions, :tier, :string
    add_column :mimo_transactions, :item_label, :string
    add_column :mimo_transactions, :thanked_at, :datetime
    change_column_null :mimo_transactions, :mimo_item_id, true
  end
end
