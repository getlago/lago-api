# frozen_string_literal: true

FactoryBot.define do
  factory :product_filter_value do
    organization
    product_filter { association(:product_filter, organization:) }
    billable_metric_filter { association(:billable_metric_filter, organization:, values: %w[us eu apac]) }
    value { billable_metric_filter.values.first }
  end
end
