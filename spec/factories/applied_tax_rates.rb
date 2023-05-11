# frozen_string_literal: true

FactoryBot.define do
  factory :applied_tax_rate do
    customer
    tax_rate
  end
end
