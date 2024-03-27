# frozen_string_literal: true

FactoryBot.define do
  factory :wallet_transaction do
    wallet
    transaction_type { "inbound" }
    status { "settled" }
    amount { "1.00" }
    credit_amount { "1.00" }
    settled_at { Time.zone.now }
  end
end
