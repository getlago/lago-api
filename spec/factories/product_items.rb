# frozen_string_literal: true

FactoryBot.define do
  factory :product_item do
    organization
    product { association(:product, organization:) }
    item_type { "usage" }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    name { Faker::Name.name }
    billable_metric { association(:billable_metric, organization:) }

    trait :usage do
      item_type { "usage" }
      billable_metric { association(:billable_metric, organization:) }
    end

    trait :fixed do
      item_type { "fixed" }
      billable_metric { nil }
    end

    trait :subscription do
      item_type { "subscription" }
      billable_metric { nil }
    end
  end
end
