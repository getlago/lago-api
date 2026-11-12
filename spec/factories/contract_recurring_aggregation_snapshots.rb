# frozen_string_literal: true

FactoryBot.define do
  factory :contract_recurring_aggregation_snapshot do
    organization
    contract { association(:contract, organization:, customer: association(:customer, organization:)) }
    product { association(:product, organization:) }
    billable_metric { product.billable_metric }
    to_datetime { Time.current.beginning_of_month }
    watermark { Time.current }
    units { 0 }
  end
end
