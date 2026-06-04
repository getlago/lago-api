# frozen_string_literal: true

FactoryBot.define do
  factory :rate_phase do
    organization
    plan_rate_card { association(:plan_rate_card, organization:) }
    subscription_rate_card { nil }
    position { 1 }
    billing_interval_cycle_count { nil }
    rate_override_id { nil }

    trait :subscription_level do
      plan_rate_card { nil }
      subscription_rate_card { association(:subscription_rate_card, organization:) }
    end
  end
end
