# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_wallet_triggered_alert, class: "UsageMonitoring::CatalogWalletTriggeredAlert" do
    alert factory: :catalog_wallet_alert
    organization { alert.organization }
    catalog_wallet { alert.catalog_wallet }
    current_value { 1000 }
    previous_value { 3000 }
    triggered_at { Time.current }
    crossed_thresholds { [{code: "low", value: BigDecimal(2000), recurring: false}] }
  end
end
