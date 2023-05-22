# frozen_string_literal: true

FactoryBot.define do
  factory :applied_tax do
    customer
    tax
  end
end
