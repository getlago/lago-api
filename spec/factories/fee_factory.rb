# frozen_string_literal: true

FactoryBot.define do
  factory :fee do
    invoice
    charge { nil }
    add_on { nil }
    subscription

    amount_cents { 200 }
    amount_currency { 'EUR' }

    vat_amount_cents { 2 }
    vat_amount_currency { 'EUR' }
  end
end
