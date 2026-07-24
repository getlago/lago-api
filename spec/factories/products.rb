# frozen_string_literal: true

FactoryBot.define do
  factory :product do
    organization
    name { Faker::Commerce.product_name }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    description { "test description" }
    invoice_display_name { Faker::Commerce.product_name }
  end
end
