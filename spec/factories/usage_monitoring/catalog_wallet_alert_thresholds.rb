# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_wallet_alert_threshold, class: "UsageMonitoring::CatalogWalletAlertThreshold" do
    catalog_wallet_alert
    organization { catalog_wallet_alert&.organization || plan_wallet_alert.organization }
    code { "low" }
    value { 2000 }

    trait :template do
      catalog_wallet_alert { nil }
      plan_wallet_alert
    end
  end
end
