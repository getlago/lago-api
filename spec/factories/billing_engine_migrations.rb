# frozen_string_literal: true

FactoryBot.define do
  factory :billing_engine_migration do
    organization
    shadow_organization { association(:organization, feature_flags: ["product_catalog"]) }
    status { "shadowing" }
    plan_mapping { {} }
  end
end
