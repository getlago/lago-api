# frozen_string_literal: true

require 'sidekiq/web'

Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq' if ENV['LAGO_SIDEKIQ_WEB']

  if Rails.env.development?
    mount GraphiQL::Rails::Engine, at: '/graphiql', graphql_path: '/graphql'
  end

  post '/graphql', to: 'graphql#execute'

  # Health Check status
  get '/health', to: 'application#health'

  namespace :api do
    namespace :v1 do
      resources :customers, only: %i[create] do
        get :current_usage
      end

      resources :subscriptions, only: %i[create update index]
      delete '/subscriptions/:id', to: 'subscriptions#terminate', as: :terminate

      resources :add_ons, param: :code
      resources :billable_metrics, param: :code
      resources :coupons, param: :code
      resources :events, only: %i[create show]
      resources :applied_coupons, only: %i[create]
      resources :applied_add_ons, only: %i[create]
      resources :invoices, only: %i[update show index] do
        post :download, on: :member
      end
      resources :plans, param: :code
      resources :wallet_transactions, only: :create
      resources :wallets, only: %i[create update show index]
      delete '/wallets/:id', to: 'wallets#terminate'
      post '/events/batch', to: 'events#batch'

      put '/organizations', to: 'organizations#update'

      resources :webhooks, only: %i[] do
        get :public_key, on: :collection
      end
    end
  end

  resources :webhooks, only: [] do
    post 'stripe/:organization_id', to: 'webhooks#stripe', on: :collection, as: :stripe
  end
end
