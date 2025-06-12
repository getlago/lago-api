# frozen_string_literal: true

FactoryBot.define do
  factory :alert, class: "UsageMonitoring::Alert" do
    association :organization
    subscription_external_id { create(:subscription, organization: organization).external_id }
    name { "General Alert" }
    sequence(:code) { |n| "default#{n}" }
    alert_type { "current_usage_amount" }

    transient do
      thresholds { [15_00] }
      recurring_threshold { nil }
    end

    after(:create) do |alert, evaluator|
      if evaluator.thresholds
        thresholds_attributes = evaluator.thresholds.map do |v|
          {value: v, code: "warn#{v}", organization_id: alert.organization_id}
        end
        alert.thresholds.create! thresholds_attributes
      end

      if evaluator.recurring_threshold
        alert.thresholds.create!({
          value: evaluator.recurring_threshold, code: "rec", recurring: true, organization_id: alert.organization_id
        })
      end
    end
  end

  trait :processed do
    previous_value { 8_00 }
    last_processed_at { DateTime.new(2000, 1, 1, 12, 0, 0) }
  end

  factory :usage_current_amount_alert,
    class: "UsageMonitoring::CurrentUsageAmountAlert",
    parent: :alert do
    alert_type { "current_usage_amount" }
  end

  factory :lifetime_usage_amount_alert,
    class: "UsageMonitoring::LifetimeUsageAmountAlert",
    parent: :alert do
    alert_type { "lifetime_usage_amount" }
  end

  factory :billable_metric_current_usage_amount_alert,
    class: "UsageMonitoring::BillableMetricCurrentUsageAmountAlert",
    parent: :alert do
    alert_type { "billable_metric_current_usage_amount" }
    billable_metric { association(:billable_metric, organization:) }
  end

  factory :billable_metric_current_usage_units_alert,
    class: "UsageMonitoring::BillableMetricCurrentUsageUnitsAlert",
    parent: :alert do
    alert_type { "billable_metric_current_usage_units" }
    billable_metric { association(:billable_metric, organization:) }
  end
end
