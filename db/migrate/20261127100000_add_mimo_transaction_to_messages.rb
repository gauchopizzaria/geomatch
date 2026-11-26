# Mimos na conversa:
#   - quem envia um mimo ganha um balão "Mimo" na conversa com quem recebeu
#     (a mensagem é de quem enviou e aponta para o mimo);
#   - o agradecimento (MimoThanksController) também aponta para o mimo, e o balão cita
#     "Agradeceu pelo mimo: Rosa vermelha".
# Quem é quem sai do remetente da mensagem: igual ao de quem enviou o mimo = o mimo;
# diferente = o agradecimento.
class AddMimoTransactionToMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :messages, :mimo_transaction, type: :uuid, null: true, index: true,
                  foreign_key: { on_delete: :nullify }
  end
end
