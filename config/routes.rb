# frozen_string_literal: true

Rails.application.routes.draw do
  mount Sidekiq::Web, at: '/sidekiq' if defined? Sidekiq::Web
  mount Karafka::Web::App, at: '/karafka' if ENV['KARAFKA_WEB']

  mount GraphiQL::Rails::Engine, at: '/graphiql', graphql_path: '/graphql' if Rails.env.development?

  post '/graphql', to: 'graphql#execute'

  # Health Check status
  get '/health', to: 'application#health'

  namespace :api do
    namespace :v1 do
      namespace :analytics do
        get :gross_revenue, to: 'gross_revenues#index', as: :gross_revenue
        get :invoiced_usage, to: 'invoiced_usages#index', as: :invoiced_usage
        get :invoice_collection, to: 'invoice_collections#index', as: :invoice_collection
        get :mrr, to: 'mrrs#index', as: :mrr
        get :overdue_balance, to: 'overdue_balances#index', as: :overdue_balance
      end

      resources :customers, param: :external_id, only: %i[create index show destroy] do
        get :portal_url

        get :current_usage, to: 'customers/usage#current'
        get :past_usage, to: 'customers/usage#past'

        post :checkout_url

        scope module: :customers do
          resources :applied_coupons, only: %i[destroy]
        end
      end

      resources :subscriptions, only: %i[create update show index], param: :external_id
      delete '/subscriptions/:external_id', to: 'subscriptions#terminate', as: :terminate

      resources :add_ons, param: :code
      resources :billable_metrics, param: :code

      resources :coupons, param: :code
      resources :credit_notes, only: %i[create update show index] do
        post :download, on: :member
        put :void, on: :member
        post :estimate, on: :collection
      end
      resources :events, only: %i[create show] do
        post :estimate_fees, on: :collection
      end
      resources :applied_coupons, only: %i[create index]
      resources :fees, only: %i[show update index destroy]
      resources :invoices, only: %i[create update show index] do
        post :download, on: :member
        post :void, on: :member
        post :lose_dispute, on: :member
        post :retry_payment, on: :member
        post :payment_url, on: :member
        put :refresh, on: :member
        put :finalize, on: :member
      end
      resources :plans, param: :code
      resources :taxes, param: :code
      resources :wallet_transactions, only: :create
      get '/wallets/:id/wallet_transactions', to: 'wallet_transactions#index'
      resources :wallets, only: %i[create update show index]
      delete '/wallets/:id', to: 'wallets#terminate'
      post '/events/batch', to: 'events#batch'

      get '/organizations', to: 'organizations#show'
      put '/organizations', to: 'organizations#update'
      get '/organizations/grpc_token', to: 'organizations#grpc_token'

      resources :webhook_endpoints, only: %i[create index show destroy update]
      resources :webhooks, only: %i[] do
        get :public_key, on: :collection
        get :json_public_key, on: :collection
      end
    end
  end

  resources :webhooks, only: [] do
    post 'stripe/:organization_id', to: 'webhooks#stripe', on: :collection, as: :stripe
    post 'gocardless/:organization_id', to: 'webhooks#gocardless', on: :collection, as: :gocardless
    post 'adyen/:organization_id', to: 'webhooks#adyen', on: :collection, as: :adyen
  end

  namespace :admin do
    resources :memberships, only: %i[create]
    resources :organizations, only: %i[update]
    resources :invoices do
      post :regenerate, on: :member
    end
  end

  if Rails.env.development?
    namespace :dev_tools do
      get '/invoices/:id', to: 'invoices#show'
    end
  end

  match '*unmatched' => 'application#not_found',
    :via => %i[get post put delete patch],
    :constraints => lambda { |req|
      req.path.exclude?('rails/active_storage')
    }
end
