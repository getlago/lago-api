# frozen_string_literal: true

FactoryBot.define do
  factory :rate_phase do
    organization
    plan_product_item { association(:plan_product_item, organization:) }
    subscription_product_item { nil }
    position { 1 }
    billing_interval_cycle_count { nil }
    rate_override_id { nil }

    trait :subscription_level do
      plan_product_item { nil }
      subscription_product_item { association(:subscription_product_item, organization:) }
    end
  end
end
