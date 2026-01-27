class MatchesController < ApplicationController
  before_action :authenticate_user!

  def index
    # Usa o escopo for_user em vez de current_user.matches (ficará mais limpo e confiável)
    # @matches = Match.for_user(current_user.id).page(params[:page]).per(10)
    
    # 1. Busca todos os matches do usuário
    all_matches = Match.for_user(current_user.id).includes(:messages, :user, :matched_user)

    # 2. Separa os matches
    @matches_initiated = []
    @matches_uninitiated = []

    all_matches.each do |match|
      if match.initiated_conversation?
        @matches_initiated << match
      else
        @matches_uninitiated << match
      end
    end

    # Opcional: Aplicar paginação apenas aos matches iniciados, se necessário.
    # @matches_initiated = Kaminari.paginate_array(@matches_initiated).page(params[:page]).per(10)
    
    # Nota: A paginação foi removida para simplificar a demonstração. 
    # Se a paginação for necessária, ela deve ser aplicada ao @matches_initiated.
  end

  def show
    @match = Match.find(params[:id])
    @messages = @match.messages.order(created_at: :asc)
    @message = Message.new
  end

  def start_chat
    # 1. Encontra o usuário alvo pelo ID passado na URL
    target_user = User.find(params[:user_id])

    # 2. Verifica se já existe um match entre os dois (em qualquer direção)
    @match = Match.where(user: current_user, matched_user: target_user)
                  .or(Match.where(user: target_user, matched_user: current_user))
                  .first

    # 3. Se não existir match, cria um novo (Lógica de "Chat Imediato")
    unless @match
      @match = Match.create!(user: current_user, matched_user: target_user)
    end

    # 4. Redireciona para a tela de chat (show.html.erb)
    redirect_to match_path(@match)
  rescue ActiveRecord::RecordNotFound
    redirect_to lead_path, alert: "Usuário não encontrado."
  end
end