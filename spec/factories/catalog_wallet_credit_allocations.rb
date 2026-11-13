# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_wallet_credit_allocation do
    organization
    catalog_wallet { association(:catalog_wallet, organization:) }
    product { association(:product, organization:) }
    sequence(:code) { |n| "allocation-#{n}" }
    trigger { "billing_cycle" }
    credit_amount_cents { 10_000 }

    trait :ongoing_balance do
      product { nil }
      trigger { "ongoing_balance" }
      threshold_amount_cents { 2_000 }
      purchase_amount_cents { 8_000 }
      invoice_requires_successful_payment { true }
    end
  end
end
