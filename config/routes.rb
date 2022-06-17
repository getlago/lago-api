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
      resources :customers, only: %i[create]

      resources :subscriptions, only: %i[create]
      delete '/subscriptions', to: 'subscriptions#terminate', as: :terminate

      resources :events, only: %i[create show]
      resources :applied_coupons, only: %i[create]
      resources :applied_add_ons, only: %i[create]
      resources :invoices, only: %i[update]

      resources :webhooks, only: %i[] do
        get :public_key, on: :collection
      end
    end
  end
end
