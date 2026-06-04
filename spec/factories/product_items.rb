# frozen_string_literal: true

FactoryBot.define do
  factory :product_item do
    organization
    product { association(:product, organization:) }
    name { Faker::Commerce.product_name }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    item_type { "usage" }
    billable_metric { association(:billable_metric, organization:) }

    trait :fixed do
      item_type { "fixed" }
      billable_metric { nil }
    end

    trait :standalone do
      product { nil }
    end

    trait :with_filters do
      transient do
        filters_count { 1 }
      end

      after(:build) do |product_item, evaluator|
        product_item.filters = build_list(
          :product_item_filter,
          evaluator.filters_count,
          organization: product_item.organization,
          product_item:
        )
      end
    end
  end
end
