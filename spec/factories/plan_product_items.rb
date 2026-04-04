# frozen_string_literal: true

FactoryBot.define do
  factory :plan_product_item do
    organization
    plan { association(:plan, organization:) }
    product_item { association(:product_item, organization:) }
  end
end
