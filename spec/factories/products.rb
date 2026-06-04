# frozen_string_literal: true

FactoryBot.define do
  factory :product do
    organization
    product_category { association(:product_category, organization:) }
    name { Faker::Commerce.product_name }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    product_type { "usage" }
    billable_metric { association(:billable_metric, organization:) }

    trait :fixed do
      product_type { "fixed" }
      billable_metric { nil }
    end

    trait :standalone do
      product_category { nil }
    end
  end
end
