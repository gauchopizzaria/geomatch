Rails.application.routes.draw do
  # Página inicial pública
  root "public#landing"

  # Páginas públicas
  get "/terms",    to: "public#terms",   as: :terms_of_use
  get "/privacy",  to: "public#privacy", as: :privacy_policy
  get "/profiles", to: "public#profiles", as: :public_profiles

  # Descoberta (mapa)
  get "/discover", to: "users#discover", as: :discover

  # Nova tela de Descoberta (Lead/Swipe)
  get "/lead", to: "users#lead", as: :lead

  # Endpoint JSON para busca de usuários próximos
  get "/users/nearby", to: "users#nearby"

  # Likes (curtidas)
  resources :likes, only: [:create, :destroy]

  # Matches e mensagens dentro do chat
  resources :matches, only: [:index, :show] do
    resources :messages, only: [:create]
  end

  # Autenticação (Devise)
  devise_for :users

  # Usuários (exibição e atualização)
  resources :users, only: [:show, :update]

  # ADIÇÃO CORRIGIDA PARA A TELA "MEU PERFIL"
  # Usa 'resource :profile' para evitar conflito com a rota /users/edit do Devise
  # Mapeia para o UsersController
  resource :profile, controller: 'users', only: [:edit, :update]


  # Logout rápido (atalho amigável)
  devise_scope :user do
    delete "/logout", to: "devise/sessions#destroy", as: :logout
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
