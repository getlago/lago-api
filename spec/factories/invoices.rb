# frozen_string_literal: true

FactoryBot.define do
  factory :invoice do
    customer
    organization

    issuing_date { Time.zone.now - 1.day }
    payment_due_date { issuing_date }
    payment_status { 'pending' }
    currency { 'EUR' }

    trait :draft do
      status { :draft }
    end

    trait :credit do
      invoice_type { :credit }
    end
  end
end
