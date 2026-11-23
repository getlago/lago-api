# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_wallet_alert, class: "UsageMonitoring::CatalogWalletAlert" do
    organization
    catalog_wallet { association(:catalog_wallet, organization:) }
    alert_type { "balance" }
    sequence(:code) { |n| "wallet-alert-#{n}" }
    name { "Low balance" }
  end
end
