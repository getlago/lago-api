# frozen_string_literal: true

# Nested legacy plan routes, drawn inside both the v1 and the native v2 plans
# blocks: the greedy v2 :code would otherwise swallow these paths before the
# fallback namespace is reached.
resources :charges, only: %i[index show create update destroy], param: :code, code: /.*/, controller: "/api/v1/plans/charges" do
  resources :filters, only: %i[index show create update destroy], controller: "/api/v1/plans/charges/filters"
end
resources :fixed_charges, only: %i[index show create update destroy], param: :code, code: /.*/, controller: "/api/v1/plans/fixed_charges"
resources :entitlements, only: %i[index show create destroy], param: :code, code: /.*/, controller: "/api/v1/plans/entitlements" do
  resources :privileges, only: %i[destroy], param: :code, code: /.*/, controller: "/api/v1/plans/entitlements/privileges"
end
patch :entitlements, controller: "/api/v1/plans/entitlements", action: :update
resource :metadata, only: %i[create update destroy], controller: "/api/v1/plans/metadata" do
  delete ":key", action: :destroy_key, on: :member
end
