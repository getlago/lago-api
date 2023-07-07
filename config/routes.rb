# frozen_string_literal: true

require 'sidekiq/web'

# NOTE: Configure Sidekiq Web session middleware
Sidekiq::Web.use(ActionDispatch::Cookies)
Sidekiq::Web.use(ActionDispatch::Session::CookieStore, key: '_interslice_session')

Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq' if ENV['LAGO_SIDEKIQ_WEB'] == 'true'

  mount GraphiQL::Rails::Engine, at: '/graphiql', graphql_path: '/graphql' if Rails.env.development?

  post '/graphql', to: 'graphql#execute'

  # Health Check status
  get '/health', to: 'application#health'

  namespace :api do
    namespace :v1 do
      resources :customers, param: :external_id, only: %i[create index show destroy] do
        get :current_usage
        get :portal_url

        scope module: :customers do
          resources :applied_coupons, only: %i[destroy]
          resources :applied_taxes, only: %i[create destroy], param: :tax_code
        end
      end

      resources :subscriptions, only: %i[create update index], param: :external_id
      delete '/subscriptions/:external_id', to: 'subscriptions#terminate', as: :terminate

      resources :add_ons, param: :code
      resources :billable_metrics, param: :code
      get '/billable_metrics/:code/groups', to: 'billable_metrics/groups#index', as: 'billable_metric_groups'

      resources :coupons, param: :code
      resources :credit_notes, only: %i[create update show index] do
        post :download, on: :member
        put :void, on: :member
      end
      resources :events, only: %i[create show] do
        post :estimate_fees, on: :collection
      end
      resources :applied_coupons, only: %i[create index]
      resources :applied_add_ons, only: %i[create]
      resources :fees, only: %i[show update index]
      resources :invoices, only: %i[create update show index] do
        post :download, on: :member
        post :retry_payment, on: :member
        put :refresh, on: :member
        put :finalize, on: :member
      end
      resources :plans, param: :code do
        scope module: :plans do
          resources :applied_taxes, only: %i[create destroy], param: :tax_code
        end
      end
      resources :taxes, param: :code
      resources :wallet_transactions, only: :create
      get '/wallets/:id/wallet_transactions', to: 'wallet_transactions#index'
      resources :wallets, only: %i[create update show index]
      delete '/wallets/:id', to: 'wallets#terminate'
      post '/events/batch', to: 'events#batch'

      put '/organizations', to: 'organizations#update'

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

  match '*unmatched' => 'application#not_found',
        via: %i[get post put delete patch],
        constraints: lambda { |req|
          req.path.exclude?('rails/active_storage')
        }
end
