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

    trait :succeeded do
      payment_status { :succeeded }
      succeeded_at { Time.current }
    end

    trait :failed do
      payment_status { :failed }
      failed_at { Time.current }
    end

    trait :refunded do
      payment_status { :refunded }
      refunded_at { Time.current }
    end
  end

  factory :charge_fee, parent: :fee do
    invoice
    charge factory: :standard_charge
    fee_type { 'charge' }

    invoiceable_type { 'Charge' }
    invoiceable_id { charge.id }

    properties do
      {
        'from_datetime' => Date.parse('2022-08-01 00:00:00'),
        'to_datetime' => Date.parse('2022-08-30 23:59:59'),
        'charges_from_datetime' => Date.parse('2022-08-01 00:00:00'),
        'charges_to_datetime' => Date.parse('2022-08-30 23:59:59'),
      }
    end
  end

  factory :add_on_fee, class: 'Fee' do
    invoice
    applied_add_on
    fee_type { 'add_on' }
    subscription { nil }

    amount_cents { 200 }
    amount_currency { 'EUR' }

    invoiceable factory: :add_on

    vat_amount_cents { 2 }
    vat_amount_currency { 'EUR' }
  end
end
