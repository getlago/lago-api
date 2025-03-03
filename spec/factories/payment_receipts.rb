# frozen_string_literal: true

FactoryBot.define do
  factory :payment_receipt do
    number { Faker::Alphanumeric.alphanumeric(number: 12) }
    payment
    organization
  end
end
