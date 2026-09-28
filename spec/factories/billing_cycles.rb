# frozen_string_literal: true

FactoryBot.define do
  factory :billing_cycle do
    organization
    contract_rate_card { association(:contract_rate_card, organization:) }
    cycle_index { 0 }
    started_at { Time.utc(2026, 1, 1) }
    ended_at { started_at + 1.month }
    timezone { "UTC" }
  end
end
