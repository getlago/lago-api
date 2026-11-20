# frozen_string_literal: true

FactoryBot.define do
  factory :contract_alert_threshold, class: "UsageMonitoring::ContractAlertThreshold" do
    alert factory: :contract_alert
    organization { alert.organization }
    code { "warn" }
    value { rand(40..500) * 100 }
  end
end
