# frozen_string_literal: true

FactoryBot.define do
  factory :billing_segment do
    skip_create
    organization
    customer { association(:customer, organization:) }
    contract { association(:contract, organization:, customer:) }
    contract_rate_card { association(:contract_rate_card, organization:, contract:) }
    billable_metric_code { contract_rate_card.rate_card.product.billable_metric&.code }
    rate_card_rate { association(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card) }
    rate_override { nil }
    pricing_unit { nil }
    rate_properties { (rate_override || rate_card_rate)&.properties || {} }
    currency { rate_card_rate&.rate_card&.currency || "EUR" }
    billing_at { Time.current }
    cycle_started_at { Time.current.beginning_of_day }
    started_at { cycle_started_at }
    ended_at { BillingSegment.inclusive_end(cycle_started_at + 1.month) }
    proration_ratio { BigDecimal("1") }
  end
end
