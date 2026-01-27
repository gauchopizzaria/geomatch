class MatchesController < ApplicationController
  before_action :authenticate_user!

  def index
    # 1. Busca todos os matches do usuário
    all_matches = Match.for_user(current_user.id).includes(:messages, :user, :matched_user)

    # 2. Separa os matches
    @matches_initiated = []
    @matches_uninitiated = []

    all_matches.each do |match|
      # Verifica se tem mensagens reais na conversa
      if match.messages.any?
        @matches_initiated << match
      else
        # --- LÓGICA DE FILTRO PARA MATCHES VAZIOS ---
        other_user = match.other_user(current_user)
        
        # --- CORREÇÃO AQUI ---
        # Trocamos 'user_id' por 'liker_id' conforme seu banco de dados
        
        # Eu curti ele?
        i_liked = Like.exists?(liker_id: current_user.id, liked_id: other_user.id)
        
        # Ele me curtiu?
        he_liked = Like.exists?(liker_id: other_user.id, liked_id: current_user.id)
        
        is_mutual_match = i_liked && he_liked

        # Só adiciona aos "Matches Recentes" se for mútuo.
        if is_mutual_match
          @matches_uninitiated << match
        end
      end
    end
  end

  def show
    @match = Match.find(params[:id])
    @messages = @match.messages.order(created_at: :asc)
    @message = Message.new
  end

  def start_chat
    target_user = User.find(params[:user_id])

    @match = Match.where(user: current_user, matched_user: target_user)
                  .or(Match.where(user: target_user, matched_user: current_user))
                  .first

    unless @match
      @match = Match.create!(user: current_user, matched_user: target_user)
    end

    redirect_to match_path(@match)
  rescue ActiveRecord::RecordNotFound
    redirect_to lead_path, alert: "Usuário não encontrado."
  end
end