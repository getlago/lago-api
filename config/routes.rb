# frozen_string_literal: true

Rails.application.routes.draw do
  if ENV["LAGO_SIDEKIQ_WEB"] == "true"
    mount Sidekiq::Web, at: "/sidekiq" if defined?(Sidekiq::Web)
    mount Sidekiq::Prometheus::Exporter, at: "/sidekiq/prometheus/metrics" if defined? Sidekiq::Prometheus::Exporter
  end
  mount Karafka::Web::App, at: "/karafka" if ENV["LAGO_KARAFKA_WEB"]
  mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql" if Rails.env.development?
  mount Yabeda::Prometheus::Exporter, at: "/metrics"
  mount ActionCable.server, at: "/cable"

  post "/graphql", to: "graphql#execute"

  # Health Check status
  get "/health", to: "application#health"
  get "/ready", to: "application#ready"

  namespace :data_api do
    namespace :v1 do
      resources :charges, only: [] do
        post :forecasted_usage_amount, on: :member
        post :bulk_forecasted_usage_amount, on: :collection
      end
    end
  end

  namespace :api do
    namespace :v1 do
      draw(:shared_api)
    end

    namespace :v2, module: :v1 do
      draw(:shared_api)
    end

    namespace :v2 do
      resources :product_items, only: %i[index show create update destroy] do
        resources :filters, only: %i[index show create update destroy], controller: "product_items/filters"
      end
      resources :products, param: :code, code: /.*/, only: %i[index show create update destroy]
      resources :rate_cards, only: %i[index show create update destroy] do
        resources :rates, only: %i[index show create update destroy], controller: "rate_cards/rates"
      end
      resources :plan_product_items, only: %i[index show create] do
        scope module: :plan_product_items do
          get "rate_phases", to: "rate_phases#index"
          put "rate_phases", to: "rate_phases#replace"
        end
      end
    end
  end
  resources :webhooks, only: [] do
    post "stripe/:organization_id", to: "webhooks#stripe", on: :collection, as: :stripe

    post "cashfree/:organization_id", to: "webhooks#cashfree", on: :collection, as: :cashfree
    post "flutterwave/:organization_id", to: "webhooks#flutterwave", on: :collection, as: :flutterwave
    post "gocardless/:organization_id", to: "webhooks#gocardless", on: :collection, as: :gocardless
    post "adyen/:organization_id", to: "webhooks#adyen", on: :collection, as: :adyen
    post "moneyhash/:organization_id", to: "webhooks#moneyhash", on: :collection, as: :moneyhash
  end

  namespace :admin do
    resources :memberships, only: %i[create]
    resources :organizations, only: %i[update create]
    resources :invoices do
      post :regenerate, on: :member
    end
  end

  if Rails.env.development?
    namespace :dev_tools do
      get "/invoices/:id", to: "invoices#show"
      get "/payment_receipts/:id", to: "payment_receipts#show"
    end
  end

  match "*unmatched" => "application#not_found",
    :via => %i[get post put delete patch],
    :constraints => lambda { |req|
      req.path.exclude?("rails/active_storage")
    }
end
