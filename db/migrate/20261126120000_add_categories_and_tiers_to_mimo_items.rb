# Catálogo novo de Mimos (tabela interna "Catálogo de mimos e valores"): cada mimo
# tem uma categoria e três níveis — Simples, Especial e Premium —, cada um com o
# próprio nome ("rosa", "rosa vermelha", "buquê de rosas") e preço.
#
# tiers: [{ "key" => "simples", "label" => "rosa", "price_cents" => 290 }, ...]
# price_cents continua sendo o "a partir de" (preço do Simples): é o que o app
# mobile já lê em /mimo_items/catalog.
class AddCategoriesAndTiersToMimoItems < ActiveRecord::Migration[8.1]
  def change
    add_column :mimo_items, :category, :string
    add_column :mimo_items, :tiers, :jsonb, null: false, default: []
    add_index  :mimo_items, :category
  end
end
