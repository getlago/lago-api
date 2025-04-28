# frozen_string_literal: true

FactoryBot.define do
  factory :triggered_alert, class: "UsageMonitoring::TriggeredAlert" do
    association :alert
    association :organization
    association :subscription
    current_value { 3000 }
    previous_value { 1000 }
    triggered_at { Time.current }
  end
end
