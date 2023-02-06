# frozen_string_literal: true

FactoryBot.define do
  factory :invoice do
    customer
    organization

    issuing_date { Time.zone.now - 1.day }
    payment_status { 'pending' }
    amount_currency { 'EUR' }
    total_amount_currency { 'EUR' }

    trait :draft do
      status { :draft }
    end

    trait :credit do
      invoice_type { :credit }
    end
  end
end
