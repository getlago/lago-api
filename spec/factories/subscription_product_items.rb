# frozen_string_literal: true

FactoryBot.define do
  factory :subscription_product_item do
    organization
    subscription { association(:subscription, organization:) }
    product_item { association(:product_item, organization:) }
    billing_anchor_date { Date.current }
    next_billing_at { Time.current }
    started_at { Time.current }
    ended_at { nil }
    units { nil }
  end
end
