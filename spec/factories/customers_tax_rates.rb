# frozen_string_literal: true

FactoryBot.define do
  factory :customers_tax_rate do
    customer
    tax_rate
  end
end
