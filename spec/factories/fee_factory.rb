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

  factory :charge_fee, parent: :fee do
    invoice
    charge
    fee_type { 'charge' }

    invoiceable_type { 'Charge' }
    invoiceable_id { charge.id }

    properties do
      {
        'charges_from_date' => Date.parse('2022-08-01'),
        'charges_to_date' => Date.parse('2022-08-30'),
      }
    end
  end
end
