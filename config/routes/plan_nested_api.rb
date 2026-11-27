# frozen_string_literal: true

# Legacy plan routes that the native v2 plans block still draws, as in v1: the
# greedy v2 :code would otherwise swallow these paths before the fallback
# namespace is reached. The entitlement routes are native on v2, so v1 draws
# them in shared_api.rb, and the metadata routes follow them (plan_metadata_api.rb).
resources :charges, only: %i[index show create update destroy], param: :code, code: /.*/, controller: "/api/v1/plans/charges" do
  resources :filters, only: %i[index show create update destroy], controller: "/api/v1/plans/charges/filters"
end
resources :fixed_charges, only: %i[index show create update destroy], param: :code, code: /.*/, controller: "/api/v1/plans/fixed_charges"
