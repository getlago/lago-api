# frozen_string_literal: true

FactoryBot.define do
  factory :subscription_rate_schedule do
    organization
    subscription { association(:subscription, organization:) }
    product_item { association(:product_item, organization:) }
    rate_schedule { association(:rate_schedule, organization:, product_item:) }
    status { "active" }
    intervals_billed { 0 }
    started_at { Time.current }
  end
end
