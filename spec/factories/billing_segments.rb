# frozen_string_literal: true

FactoryBot.define do
  factory :billing_segment do
    organization
    customer { association(:customer, organization:) }
    contract { association(:contract, organization:, customer:) }
    contract_rate_card { association(:contract_rate_card, organization:, contract:) }
    rate_card_rate { association(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card) }
    rate_override { nil }
    pricing_unit { nil }
    invoice { nil }
    rate_properties { (rate_override || rate_card_rate)&.properties || {} }
    currency { rate_card_rate&.rate_card&.currency || "EUR" }
    billing_at { Time.current }
    cycle_started_at { Time.current.beginning_of_day }
    started_at { cycle_started_at }
    ended_at { cycle_started_at + 1.month - Rational(1, 1_000_000) }
    status { :pending }
  end
end
