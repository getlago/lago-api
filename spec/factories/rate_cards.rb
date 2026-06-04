# frozen_string_literal: true

FactoryBot.define do
  factory :rate_card do
    organization
    product_item { association(:product_item, organization:) }
    name { Faker::Commerce.product_name }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    description { "test description" }
    currency { "EUR" }
    billing_timing { "arrears" }
    proration { "full" }
    display_on_invoice { true }

    trait :advance do
      billing_timing { "advance" }
    end

    trait :with_filter do
      product_item_filter { association(:product_item_filter, organization:, product_item:) }
    end
  end
end
