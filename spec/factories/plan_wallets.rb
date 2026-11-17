# frozen_string_literal: true

FactoryBot.define do
  factory :plan_wallet do
    organization
    catalog_plan { association(:catalog_plan, organization:) }
    sequence(:code) { |n| "plan-wallet-#{n}" }
    name { "Prepaid credits" }
    currency { "EUR" }
  end
end
