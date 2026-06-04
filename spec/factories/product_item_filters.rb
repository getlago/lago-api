# frozen_string_literal: true

FactoryBot.define do
  factory :product_item_filter do
    organization
    product_item { association(:product_item, organization:) }
    name { Faker::Commerce.department }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    description { "test description" }
    invoice_display_name { Faker::Commerce.department }

    trait :with_values do
      transient do
        values_count { 1 }
      end

      after(:build) do |filter, evaluator|
        filter.values = build_list(
          :product_item_filter_value,
          evaluator.values_count,
          organization: filter.organization,
          product_item_filter: filter
        )
      end
    end
  end
end
