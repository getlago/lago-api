# frozen_string_literal: true

FactoryBot.define do
  factory :billing_cycle do
    organization
    subscription { association(:subscription, organization:) }
    subscription_product_item { association(:subscription_product_item, organization:, subscription:) }
    billing_at { Time.current }
    period_from { 1.month.ago }
    period_to { Time.current }
    status { "pending" }
    attempts { 0 }
  end
end
