# frozen_string_literal: true

FactoryBot.define do
  factory :plan_product do
    organization
    plan { association(:plan, organization:) }
    product { association(:product, organization:) }
  end
end
