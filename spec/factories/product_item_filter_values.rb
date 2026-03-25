# frozen_string_literal: true

FactoryBot.define do
  factory :product_item_filter_value do
    organization
    product_item_filter { association(:product_item_filter, organization:) }
    value { product_item_filter.billable_metric_filter.values.first }
  end
end
