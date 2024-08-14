# frozen_string_literal: true

FactoryBot.define do
  factory :payment_request do
    customer
    organization { customer.organization }
    payment_requestable { create(:payable_group, customer:) }

    amount_cents { 200 }
    amount_currency { "EUR" }
    email { Faker::Internet.email }
  end
end
