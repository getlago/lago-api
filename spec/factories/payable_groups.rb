# frozen_string_literal: true

FactoryBot.define do
  factory :payable_group do
    customer
    organization { customer.organization }
  end
end
