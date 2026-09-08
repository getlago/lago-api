# frozen_string_literal: true

FactoryBot.define do
  factory :contract_rate_card do
    organization
    contract { association(:contract, organization:) }
    rate_card { association(:rate_card, organization:) }
    billing_anchor_date { Date.current }
    next_billing_at { Time.current }
    effective_date { Date.current }
    ended_date { nil }
    units { nil }
  end
end
