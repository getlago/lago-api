# frozen_string_literal: true

FactoryBot.define do
  factory :fee do
    invoice
    charge { nil }
    subscription

    amount_cents { 200 }
    amount_currency { 'EUR' }

    vat_amount_cents { 2 }
    vat_amount_currency { 'EUR' }
  end
end
