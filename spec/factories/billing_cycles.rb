# frozen_string_literal: true

FactoryBot.define do
  factory :billing_cycle do
    organization
    contract_rate_card { association(:contract_rate_card, organization:) }
    cycle_index { 0 }
    timezone { "UTC" }
    started_at { Time.current.beginning_of_month }
    ended_at { started_at + 1.month }
    reference_started_at { started_at }
  end
end
