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

    trait :with_filters do
      transient do
        filters_count { 1 }
      end

      after(:build) do |product, evaluator|
        product.filters = build_list(
          :product_filter,
          evaluator.filters_count,
          organization: product.organization,
          product:
        )
      end
    end
  end
end
