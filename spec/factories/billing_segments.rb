# frozen_string_literal: true

FactoryBot.define do
  factory :billing_segment do
    organization
    subscription { association(:subscription, organization:) }
    customer { subscription.customer }
    subscription_rate_card { association(:subscription_rate_card, organization:, subscription:, customer:) }
    rate_card_rate { association(:rate_card_rate, organization:) }
    rate_override { nil }
    pricing_unit { nil }
    rate_properties { (rate_override || rate_card_rate).properties }
    billing_at { Time.current }
    cycle_started_at { Time.current.beginning_of_day }
    started_at { cycle_started_at }
    # The window closes at the next boundary; what is stored is the instant before it.
    ended_at { BillingSegment.inclusive_end(cycle_started_at + 1.day) }
  end
end
