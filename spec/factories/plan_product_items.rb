# frozen_string_literal: true

FactoryBot.define do
  factory :plan_product_item do
    organization
    plan { association(:plan, organization:) }
    rate_card { association(:rate_card, organization:) }
    units { nil }
  end
end
