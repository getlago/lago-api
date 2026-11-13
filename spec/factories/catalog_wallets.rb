# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_wallet do
    organization
    customer { association(:customer, organization:) }
    contract { association(:contract, organization:, customer:) }
    sequence(:code) { |n| "wallet-#{n}" }
    name { "Prepaid credits" }
    currency { "EUR" }
  end
end
