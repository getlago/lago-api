# frozen_string_literal: true

# Drawn after the entitlement routes: the nested :plan_code matches slashes, so
# drawn earlier it would take entitlement or privilege paths ending in "metadata".
resource :metadata, only: %i[create update destroy], controller: "/api/v1/plans/metadata" do
  delete ":key", action: :destroy_key, on: :member
end
