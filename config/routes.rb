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

  namespace :api do
    namespace :v1 do
      resources :activity_logs, param: :activity_id, only: %i[index show]
      resources :api_logs, param: :request_id, only: %i[index show]
      resources :security_logs, param: :log_id, only: %i[index show]
      draw(:shared_api)
    end

    # Drawn first so version-specific routes win recognition; everything else on /api/v2
    # falls through to v1.
    namespace :v2 do
      resources :billing_entities, param: :code, constraints: {code: /[^\/]+/}, only: %i[index show create update]
      get "/organizations", to: "organizations#show"
      put "/organizations", to: "organizations#update"
      resources :customers, param: :external_id, constraints: {external_id: /[^\/]+/}, only: %i[index show create update destroy] do
        scope module: :customers do
          post :checkout_url, to: "checkout_urls#create"
          resources :invoices, only: :index
          resources :payments, only: :index
          resources :payment_methods, only: %i[index destroy] do
            put :set_as_default, on: :member
          end
        end
      end
      resources :taxes, param: :code, code: /.*/, only: %i[index show create update destroy]
      resources :products, param: :code, code: /.*/, only: %i[index show create update destroy] do
        resources :filters, param: :code, code: /.*/, only: %i[index show create update destroy], controller: "products/filters"
      end
      resources :product_categories, param: :code, code: /.*/, only: %i[index show create update destroy]
      resources :rate_cards, param: :code, code: /.*/, only: %i[index show create update destroy] do
        resources :rates, param: :code, code: /.*/, only: %i[index show create update destroy], controller: "rate_cards/rates"
      end
      resources :plans, param: :code, code: /.*/, only: %i[index show create update] do
        resources :applied_rate_cards, param: :code, code: /.*/, only: %i[index create show update destroy], controller: "plan_rate_cards" do
          scope module: :plan_rate_cards do
            resources :rate_phases, param: :code, code: /.*/, only: %i[index create update destroy]
          end
        end
        draw(:plan_nested_api)
      end
      # The constraint mirrors v1: without it, an external id containing a
      # dot is truncated at the format separator.
      resources :contracts, only: %i[index show create update], param: :external_id, constraints: {external_id: /[^\/]+/} do
        get :current_usage, on: :member, to: "contracts/usage#current"
        resources :applied_rate_cards, param: :code, code: /.*/, only: %i[index create show update destroy], controller: "contract_rate_cards" do
          scope module: :contract_rate_cards do
            resources :rate_phases, param: :code, code: /.*/, only: %i[index create update destroy]
          end
        end
      end
      # A contract is never destroyed — DELETE ends its lifecycle, the same
      # idiom subscriptions follow.
      delete "/contracts/:external_id", to: "contracts#terminate", constraints: {external_id: /[^\/]+/}
      resources :invoices, only: %i[index show update destroy] do
        post :void, on: :member
        post :lose_dispute, on: :member
        post :download_pdf, on: :member
        post :resend_email, on: :member
        post :retry_taxes, on: :member
        post :retry_payment, on: :member
        post :payment_url, on: :member, to: "invoices/payment_urls#create"
        put :refresh, on: :member
        put :finalize, on: :member
      end
      resources :fees, only: %i[index show update destroy]
      # The v2 log endpoints have their own route here and a matching v1 route
      # above, rather than a shared definition, so each version maps to its own
      # controller (v2 for the cursor pagination and v2 error body).
      resources :activity_logs, param: :activity_id, only: %i[index show]
      resources :api_logs, param: :request_id, only: %i[index show]
      resources :security_logs, param: :log_id, only: %i[index show]
      # An invoice route v2 does not serve is unknown on v2, not a v1 fallback.
      match "invoices(/*path)", to: "/application#not_found", via: :all
    end

    namespace :v2, module: :v1 do
      draw(:shared_api)
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

  if Rails.env.local?
    namespace :admin do
      resources :memberships, only: %i[create]
      resources :organizations, only: %i[update create]
      resources :invoices do
        post :regenerate, on: :member
      end
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
