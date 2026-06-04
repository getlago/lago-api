# frozen_string_literal: true

FactoryBot.define do
  factory :product_item_filter do
    organization
    product_item { association(:product_item, organization:) }
    name { Faker::Commerce.department }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    description { "test description" }
    invoice_display_name { Faker::Commerce.department }
  end
end
