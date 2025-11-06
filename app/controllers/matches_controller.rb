# app/controllers/matches_controller.rb
class MatchesController < ApplicationController
  before_action :authenticate_user!

  def index
    # Lógica para buscar os matches do usuário logado
    @matches = current_user.matches.order(matched_at: :desc).page(params[:page]).per(10)
  end
  # ... outros métodos
end
