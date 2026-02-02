Rails.application.routes.draw do
  # =================================================================
  # 1. AUTENTICAÇÃO (DEVISE)
  # =================================================================
  devise_for :users

  devise_scope :user do
    delete "/logout", to: "devise/sessions#destroy", as: :logout
  end

  # =================================================================
  # 2. ROTAS PÚBLICAS E GERAIS
  # =================================================================
  root "public#landing"

  # Páginas estáticas
  get "/terms",    to: "public#terms",   as: :terms_of_use
  get "/privacy",  to: "public#privacy", as: :privacy_policy
  get "/profiles", to: "public#profiles", as: :public_profiles
  get "notifications/index"

  # Stories
  resources :stories, only: [:index, :create]

  # Likes e Notificações
  resources :likes, only: [:create, :destroy]
  resources :notifications, only: [:index]

  # =================================================================
  # 3. FUNCIONALIDADES DE DISCOVERY / LEAD
  # =================================================================
  get "/discover", to: "users#discover", as: :discover

  # Lead/Swipe
  get  "/lead",        to: "users#lead",   as: :lead
  post "/lead",        to: "users#lead"
  post "/lead/reject", to: "users#reject", as: :reject_user

  # Iniciar chat direto
  post 'start_chat/:user_id', to: 'matches#start_chat', as: :start_chat

  # =================================================================
  # 4. MATCHES E MENSAGENS (CONSOLIDADO)
  # =================================================================
  # Aqui juntamos a exibição, as mensagens e a ação de limpar conversa
  resources :matches, only: [:index, :show] do
    # Rotas aninhadas (mensagens dentro do match)
    resources :messages, only: [:index, :create]
    
    # Ações de membro (agem sobre um match específico)
    member do
      delete :clear_conversation
    end
  end

  # =================================================================
  # 5. USUÁRIOS (CONSOLIDADO)
  # =================================================================
  
  # IMPORTANTE: Rotas específicas de /users/ devem vir ANTES de resources :users
  # para não confundir "nearby" com um ID de usuário (ex: users/1)
  get "/users/nearby", to: "users#nearby"

  resources :users, only: [:show, :update] do
    # Ações de membro (agem sobre um ID específico: /users/:id/block)
    member do
      post :block
    end

    # Ações de coleção (agem sobre a lista ou contexto geral: /users/update_location)
    collection do
      post :update_location
      post :toggle_visibility
    end
  end

  # Funcionalidades extras de usuário
  get "/safety_center",   to: "users#safety_center",   as: :safety_center
  get "/report_incident", to: "users#report_incident", as: :report_incident
  get "/meu-perfil",      to: "users#me_profile",      as: :my_profile

  # Edição do próprio perfil
  resource :profile, controller: 'users', only: [:edit, :update] do
    get "preview", on: :collection
  end

  # Fotos do álbum
  delete 'album_photos/:id', to: 'album_photos#destroy', as: :delete_album_photo

  # =================================================================
  # 6. PAGAMENTOS (CHECKOUT)
  # =================================================================
  
  # --- ALTERAÇÃO AQUI: Adicionada a rota para o Modal ---
  resources :plans, only: [:index] do
    collection do
      get :modal
    end
  end
  # ------------------------------------------------------

  post "/checkout", to: "checkout#create", as: :checkout
  post "/webhooks/mercado_pago", to: "webhooks/mercado_pago#create", as: :mercado_pago_webhook

  # =================================================================
  # 7. SISTEMA
  # =================================================================
  mount ActionCable.server => '/cable'
  get "up" => "rails/health#show", as: :rails_health_check
end