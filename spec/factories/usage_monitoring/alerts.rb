# frozen_string_literal: true

FactoryBot.define do
  factory :alert, class: "UsageMonitoring::Alert" do
    association :organization
    subscription_external_id { create(:subscription).external_id }
    code { "Alert" }
    alert_type { "usage_amount" }
  end
end
