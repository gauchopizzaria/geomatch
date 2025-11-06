class FixForeignKeyForMessages < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :messages, column: :match_id
    add_foreign_key :messages, :matches, column: :match_id
  end
end
