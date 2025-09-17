# frozen_string_literal: true

FactoryBot.define do
  factory :recurring_transaction_rule do
    wallet
    organization { wallet&.organization || association(:organization) }
    paid_credits { "10.00" }
    granted_credits { "10.00" }
    interval { "monthly" }
    trigger { "interval" }
    transaction_name { "Recurring Transaction Rule" }
  end
end
