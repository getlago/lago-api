# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_wallet_selector do
    organization
    catalog_wallet { association(:catalog_wallet, organization:) }
    selector_type { "fee_type" }
    fee_type { "metered" }

    trait :plan_level do
      catalog_wallet { nil }
      plan_wallet { association(:plan_wallet, organization:) }
    end
  end
end
