# frozen_string_literal: true

FactoryBot.define do
  factory :contract_alert, class: "UsageMonitoring::ContractAlert" do
    # Build the class of the alert type, as a row loaded from the database is
    initialize_with { new(alert_type:) }

    association :organization
    contract_external_id { create(:contract, customer: create(:customer, organization:)).external_id }
    name { "Contract Alert" }
    sequence(:code) { |n| "contract_alert#{n}" }
    alert_type { "usage_amount" }
    direction { "increasing" }

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

  factory :contract_usage_amount_alert,
    class: "UsageMonitoring::ContractUsageAmountAlert",
    parent: :contract_alert do
    alert_type { "usage_amount" }
  end

  factory :contract_usage_units_alert,
    class: "UsageMonitoring::ContractUsageUnitsAlert",
    parent: :contract_alert do
    alert_type { "usage_units" }
    product { association(:product, organization:) }
  end
end
