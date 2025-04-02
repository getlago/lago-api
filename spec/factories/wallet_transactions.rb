# frozen_string_literal: true

FactoryBot.define do
  factory :wallet_transaction do
    wallet
    transaction_type { "inbound" }
    status { "settled" }
    amount { "1.00" }
    credit_amount { "1.00" }
    settled_at { Time.zone.now }

    trait :failed do
      status { "failed" }
      failed_at { Time.current }
    end

    trait :with_invoice do
      transient do
        customer { association(:customer) }
      end

      invoice { association(:invoice, customer:, organization: customer.organization) }
    end
  end
end
