# frozen_string_literal: true

FactoryBot.define do
  factory :rate_schedule do
    organization
    plan_product_item { association(:plan_product_item, organization:) }
    product_item { plan_product_item.product_item }
    charge_model { "standard" }
    properties { {amount: Faker::Number.between(from: 100, to: 500).to_s} }
    billing_interval_count { 1 }
    billing_interval_unit { "month" }
    amount_currency { "EUR" }
    position { 1 }

    trait :graduated do
      charge_model { "graduated" }
      properties do
        {graduated_ranges: [
          {from_value: 0, to_value: 10, per_unit_amount: "0", flat_amount: "200"},
          {from_value: 11, to_value: nil, per_unit_amount: "0", flat_amount: "300"}
        ]}
      end
    end

    trait :pay_in_advance do
      pay_in_advance { true }
    end
  end
end
