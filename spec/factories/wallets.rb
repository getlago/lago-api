# frozen_string_literal: true

FactoryBot.define do
  factory :wallet do
    customer
    organization { customer&.organization || association(:organization) }
    name { Faker::Name.name }
    status { "active" }
    rate_amount { "1.00" }
    currency { "EUR" }
    credits_balance { 0 }
    balance_cents { 0 }
    consumed_credits { 0 }
    invoice_requires_successful_payment { false }

    trait :terminated do
      status { "terminated" }
    end

    trait :with_recurring_transaction_rules do
      recurring_transaction_rules { [association(:recurring_transaction_rule)] }
    end
  end
end
