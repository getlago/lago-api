# frozen_string_literal: true

FactoryBot.define do
  factory :billing_operation do
    organization
    contract_rate_card do
      customer = association(:customer, organization:)
      association(:contract_rate_card, organization:, contract: association(:contract, organization:, customer:))
    end
    customer { contract_rate_card.contract.customer }
    action_type { "renew_fixed_advance" }
    reason { (action_type == "reconcile_units") ? :contract_units_change : :contract_activation }
    units_before { (action_type == "reconcile_units") ? 8 : nil }
    units_after { (action_type == "reconcile_units") ? 10 : nil }
    billing_at { Time.current }
    target_cycle_started_at { Time.current.beginning_of_month }
  end
end
