# frozen_string_literal: true

FactoryBot.define do
  factory :payment_request do
    customer
    organization { customer.organization }

    amount_cents { 200 }
    amount_currency { "EUR" }
    email { Faker::Internet.email }
    payment_status { "pending" }
  end
end
