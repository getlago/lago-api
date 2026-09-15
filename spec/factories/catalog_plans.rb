# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_plan do
    organization
    name { Faker::Commerce.product_name }
    sequence(:code) { |n| "catalog-plan-#{n}" }
    currency { "EUR" }
  end
end
