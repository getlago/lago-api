# frozen_string_literal: true

FactoryBot.define do
  factory :fee do
    invoice
    charge { nil }
    add_on { nil }
    fee_type { 'subscription' }
    subscription

    amount_cents { 200 }
    amount_currency { 'EUR' }

    invoiceable_type { 'Subscription' }
    invoiceable_id { subscription.id }

    vat_amount_cents { 2 }
    vat_amount_currency { 'EUR' }
  end
end
