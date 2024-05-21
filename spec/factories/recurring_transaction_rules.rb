# frozen_string_literal: true

FactoryBot.define do
  factory :recurring_transaction_rule do
    wallet
    paid_credits { "10.00" }
    granted_credits { "10.00" }
    interval { "monthly" }
    trigger { "interval" }
  end
end
