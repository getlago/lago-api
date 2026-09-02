# frozen_string_literal: true

FactoryBot.define do
  factory :billing_cycle do
    organization
    subscription { association(:subscription, organization:) }
    customer { subscription.customer }
    subscription_rate_card { association(:subscription_rate_card, organization:, subscription:, customer:) }
    rate_card_rate { association(:rate_card_rate, organization:) }
    rate_override { nil }
    pricing_unit { nil }
    rate_properties { (rate_override || rate_card_rate).properties }
    billing_at { Time.current }
    period_from { Time.current.beginning_of_day }
    period_to { Time.current.end_of_day }
  end
end
