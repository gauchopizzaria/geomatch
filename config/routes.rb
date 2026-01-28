# config/routes.rb

Rails.application.routes.draw do
  # =================================================================
  # 1. AUTENTICAÇÃO (DEVISE) - MOVIDO PARA O TOPO PARA EVITAR CONFLITOS
  # =================================================================
  devise_for :users

  # Logout rápido (mantido aqui, logo após o Devise)
  devise_scope :user do
    delete "/logout", to: "devise/sessions#destroy", as: :logout
  end

  # =================================================================
  # 2. ROTAS PÚBLICAS E GERAIS
  # =================================================================
  # Rotas para Stories
  resources :stories, only: [:index, :create]
  
  get "notifications/index"

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
  post "/lead", to: "users#lead"
  post "/lead/reject", to: "users#reject", as: :reject_user

  # Endpoint JSON para busca de usuários próximos
  # CORREÇÃO: Movido para esta seção para garantir que seja processado antes de resources :users,
  # evitando que 'nearby' seja interpretado como um ID de usuário.
  get "/users/nearby", to: "users#nearby"

  resources :notifications, only: [:index]

  # Likes (curtidas)
  resources :likes, only: [:create, :destroy]

  # Matches e mensagens dentro do chat
  resources :matches, only: [:index, :show] do
    resources :messages, only: [:index, :create]
  end

  # =================================================================
  # 3. ROTAS DE USUÁRIOS (CONSOLIDADAS)
  # =================================================================

  # Users (exibição e atualização)
  # CONSOLIDADO: O 'show' e 'update' estavam separados, agora estão juntos.
  # O 'show' é o perfil público.
  resources :users, only: [:show, :update]

  # Tela de Central de Segurança (Ajuda)
  get "/safety_center", to: "users#safety_center", as: :safety_center

  # Tela de Denúncia Rápida
  get "/report_incident", to: "users#report_incident", as: :report_incident

  # Rota para a NOVA tela de visualização do meu perfil (Dashboard)
  get "/meu-perfil", to: "users#me_profile", as: :my_profile

  # Meu Perfil (Rota customizada para edição do usuário logado)
  # O 'resource' cria as rotas /profile/edit e PATCH /profile
  resource :profile, controller: 'users', only: [:edit, :update] do
    # NOVA ROTA: Pré-visualizar perfil (Aba Visualizar)
    get "preview", on: :collection
  end

  

 # Rotas para Usuários (Atualização de Localização e Descoberta)
  resources :users, only: [] do
    collection do
      # Endpoint para o frontend atualizar a localização do usuário logado
      post :update_location
      # Endpoint para buscar usuários próximos (já deve existir)
      # REMOVIDO: A rota get :nearby foi movida para a Seção 2 para evitar conflito com resources :users.
    end
  end

  # Rota para exclusão de foto do álbum
  delete 'album_photos/:id', to: 'album_photos#destroy', as: :delete_album_photo

  post "/checkout", to: "checkout#create", as: :checkout
  resources :plans, only: [:index]

  # =================================================================
  # 4. OUTRAS ROTAS
  # =================================================================

  # ActionCable
  mount ActionCable.server => '/cable'

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end