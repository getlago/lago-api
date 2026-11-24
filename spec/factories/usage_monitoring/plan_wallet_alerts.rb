# frozen_string_literal: true

FactoryBot.define do
  factory :plan_wallet_alert, class: "UsageMonitoring::PlanWalletAlert" do
    organization
    plan_wallet { association(:plan_wallet, organization:) }
    alert_type { "balance" }
    sequence(:code) { |n| "plan-wallet-alert-#{n}" }
    name { "Low balance" }
  end
end
