# frozen_string_literal: true

FactoryBot.define do
  factory :product_item_filter do
    organization
    product_item { association(:product_item, organization:) }
    billable_metric_filter { association(:billable_metric_filter, billable_metric: product_item.billable_metric, organization:) }
  end
end
