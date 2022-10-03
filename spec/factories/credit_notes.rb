# frozen_string_literal: true

FactoryBot.define do
  factory :credit_note do
    customer
    invoice

    status { 'available' }
    reason { 'overpaid' }
    amount_cents { 100 }
    amount_currency { 'EUR' }

    remaining_amount_cents { 100 }
    remaining_amount_currency { 'EUR' }
  end
end
