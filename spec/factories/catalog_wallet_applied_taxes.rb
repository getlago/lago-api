# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_wallet_applied_tax do
    organization
    catalog_wallet { association(:catalog_wallet, organization:) }
    tax { association(:tax, organization:) }

    trait :plan_level do
      catalog_wallet { nil }
      plan_wallet { association(:plan_wallet, organization:) }
    end
  end
end
