# frozen_string_literal: true

FactoryBot.define do
  factory :alert, class: "UsageMonitoring::Alert" do
    association :organization
    subscription_external_id { create(:subscription).external_id }
    name { "General Alert" }
    sequence(:code) { |n| "default#{n}" }
    alert_type { "usage_amount" }

    transient do
      thresholds { nil }
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

  factory :usage_amount_alert,
    class: "UsageMonitoring::UsageAmountAlert",
    parent: :alert do
    alert_type { "usage_amount" }
  end

  factory :billable_metric_usage_amount_alert,
    class: "UsageMonitoring::BillableMetricUsageAmountAlert",
    parent: :alert do
    alert_type { "billable_metric_usage_amount" }
    association :billable_metric
  end
end
