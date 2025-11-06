class MessagesController < ApplicationController
def show
  @match = Match.find(params[:id])
  # Paginação das mensagens, exibindo as mais recentes primeiro
  @messages = @match.messages.order(created_at: :desc).page(params[:page]).per(20)
  # Kaminari permite reverter a ordem para exibir as mais antigas primeiro
  # e carregar as páginas de baixo para cima (útil para chat)
  @messages = @messages.reverse
end