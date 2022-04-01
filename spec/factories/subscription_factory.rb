# frozen_string_literal: true

FactoryBot.define do
  factory :subscription do
    customer
    plan
    status { :active }
  end
end
