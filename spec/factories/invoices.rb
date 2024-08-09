# frozen_string_literal: true

FactoryBot.define do
  factory :invoice do
    customer
    organization

    issuing_date { Time.zone.now - 1.day }
    payment_due_date { issuing_date }
    payment_status { 'pending' }
    currency { 'EUR' }

    organization_sequential_id { rand(1_000_000) }

    trait :draft do
      status { :draft }
    end

    trait :credit do
      invoice_type { :credit }
    end

    trait :dispute_lost do
      payment_dispute_lost_at { DateTime.current - 1.day }
    end

    trait :with_tax_error do
      after :create do |i|
        create(:error_detail, owner: i, error_code: 'tax_error')
      end
    end

    trait :failed do
      status { :failed }
    end

    trait :subscription do
      transient do
        subscriptions { [create(:subscription)] }
      end

      invoice_type { :subscription }

      after :create do |invoice, evaluator|
        evaluator.subscriptions.each do |subscription|
          create(:invoice_subscription, invoice:, subscription:)
        end
      end
    end
  end
end
