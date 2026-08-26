# frozen_string_literal: true

FactoryBot.define do
  factory :contract_rate_card do
    organization
    contract { association(:contract, organization:) }
    rate_card { association(:rate_card, organization:) }
    billing_anchor_date { Date.current }
    next_billing_at { Time.current }
    started_at { Time.current }
    ended_at { nil }
    units { nil }
  end
end
