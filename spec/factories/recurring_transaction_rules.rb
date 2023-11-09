# frozen_string_literal: true

FactoryBot.define do
  factory :recurring_transaction_rule do
    wallet
    rule_type { 'interval' }
    paid_credits { '10.00' }
    granted_credits { '10.00' }
    interval { 'monthly' }
  end
end
