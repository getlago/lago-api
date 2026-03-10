# frozen_string_literal: true

FactoryBot.define do
  factory :order_form do
    organization
    customer
    number { "OF-2025-0001" }
    sequential_id { 1 }
    version { 1 }
    status { "draft" }
  end
end
