# frozen_string_literal: true

FactoryBot.define do
  factory :recurring_aggregation_snapshot do
    association :charge, factory: :standard_charge
    organization { charge.organization }
    billable_metric { charge.billable_metric }
    subscription { association(:subscription, organization:, plan: charge.plan, customer: association(:customer, organization:)) }
    to_datetime { Time.current.beginning_of_month }
    watermark { Time.current }
    units { 0 }
  end
end
