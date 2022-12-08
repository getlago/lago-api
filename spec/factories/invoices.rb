# frozen_string_literal: true

FactoryBot.define do
  factory :invoice do
    customer

    issuing_date { Time.zone.now - 1.day }
    payment_status { 'pending' }
    amount_currency { 'EUR' }
    total_amount_currency { 'EUR' }
  end
end
